#!/bin/bash
# docker-space-guard.sh — mantiene el uso de disco del daemon Docker bajo un límite.
#
# Si el uso supera el límite, libera espacio por niveles, de menos a más
# agresivo, y se detiene en cuanto vuelve a estar por debajo:
#   1. Contenedores detenidos, redes sin uso, imágenes dangling y build cache
#      dangling con más antigüedad que --min-age.
#   2. Toda la build cache y todas las imágenes sin contenedores que las usen.
#   3. (--truncate-logs) Vacía los logs json-file mayores que --log-max-mb.
#   4. (--prune-volumes) Volúmenes anónimos sin uso. BORRA DATOS.
#
# Códigos de salida: 0 bajo el límite (u otra instancia en curso),
#                    1 error, 2 sigue sobre el límite tras todos los niveles.
#
# Ejecutar como root (o con acceso al socket Docker y lectura de DockerRootDir).
# Con el containerd image store (Docker 29+), las imágenes viven en
# /var/lib/containerd y se mide también esa ruta.
#
# cron (cada 30 min):
#   */30 * * * * /usr/local/bin/docker-space-guard.sh
# systemd: un docker-space-guard.service (Type=oneshot, ExecStart=este script)
#   y un .timer con OnCalendar=*:0/30 y Persistent=true.

set -euo pipefail

readonly LOG_TAG="docker-space-guard"

LIMIT_GB="${DOCKER_SPACE_LIMIT_GB:-50}"
MIN_AGE="${DOCKER_SPACE_MIN_AGE:-24h}"
LOG_MAX_MB="${DOCKER_SPACE_LOG_MAX_MB:-100}"
TRUNCATE_LOGS=false
PRUNE_VOLUMES=false
DRY_RUN=false
EXTRA_PATHS=()

HAVE_LOGGER=false
command -v logger >/dev/null 2>&1 && HAVE_LOGGER=true

# usage: imprime la ayuda
usage() {
    cat <<EOF
Uso: ${0##*/} [opciones]

  -l, --limit GB        Límite en GiB (defecto: ${LIMIT_GB}; env DOCKER_SPACE_LIMIT_GB)
  -a, --min-age DUR     Antigüedad mínima para el nivel 1, p. ej. 12h (defecto: ${MIN_AGE})
  -p, --path DIR        Ruta adicional a medir (repetible)
      --truncate-logs   Habilita el nivel 3: vaciar logs grandes de contenedores
      --log-max-mb MB   Tamaño a partir del cual se vacía un log (defecto: ${LOG_MAX_MB})
      --prune-volumes   Habilita el nivel 4: borrar volúmenes anónimos sin uso
  -n, --dry-run         Muestra qué haría sin borrar nada
  -h, --help            Muestra esta ayuda
EOF
}

# log PRIORIDAD MENSAJE...: registra en syslog y, en terminal o sin logger, en stderr
log() {
    local priority="$1"
    shift
    if [[ $HAVE_LOGGER == true ]]; then
        logger -t "$LOG_TAG" -p "user.${priority}" -- "$*"
    fi
    if [[ -t 2 || $HAVE_LOGGER == false ]]; then
        printf '[%s] %s\n' "$priority" "$*" >&2
    fi
}

# die MENSAJE...: registra el error y termina con código 1
die() {
    log err "$*"
    exit 1
}

# parse_args ARGS...: rellena la configuración global a partir de la línea de comandos
parse_args() {
    while (($#)); do
        case "$1" in
        -l | --limit) LIMIT_GB="${2:?--limit requiere un valor}" && shift 2 ;;
        -a | --min-age) MIN_AGE="${2:?--min-age requiere un valor}" && shift 2 ;;
        -p | --path) EXTRA_PATHS+=("${2:?--path requiere un valor}") && shift 2 ;;
        --log-max-mb) LOG_MAX_MB="${2:?--log-max-mb requiere un valor}" && shift 2 ;;
        --truncate-logs) TRUNCATE_LOGS=true && shift ;;
        --prune-volumes) PRUNE_VOLUMES=true && shift ;;
        -n | --dry-run) DRY_RUN=true && shift ;;
        -h | --help) usage && exit 0 ;;
        *) usage >&2 && die "Opción desconocida: $1" ;;
        esac
    done
}

# validate_config: falla pronto ante valores mal escritos
validate_config() {
    [[ $LIMIT_GB =~ ^[1-9][0-9]*$ ]] || die "Límite inválido: '$LIMIT_GB' (entero en GiB)"
    [[ $LOG_MAX_MB =~ ^[1-9][0-9]*$ ]] || die "--log-max-mb inválido: '$LOG_MAX_MB'"
    [[ $MIN_AGE =~ ^[0-9]+[smh]$ ]] || die "--min-age inválido: '$MIN_AGE' (p. ej. 30m, 24h)"
    local dir
    for dir in "${EXTRA_PATHS[@]}"; do
        [[ -d $dir ]] || die "No existe la ruta adicional: $dir"
    done
}

# require_commands CMD...: comprueba que las dependencias están instaladas
require_commands() {
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || die "Falta el comando requerido: $cmd"
    done
}

# acquire_lock: evita ejecuciones solapadas (p. ej. un du lento con cron frecuente)
acquire_lock() {
    command -v flock >/dev/null 2>&1 || return 0
    local lock_file="${XDG_RUNTIME_DIR:-/run/lock}/${LOG_TAG}.lock"
    exec 9>"$lock_file" || die "No se puede crear el lock $lock_file"
    if ! flock -n 9; then
        log notice "Otra instancia está en ejecución; se omite esta pasada."
        exit 0
    fi
}

# resolve_paths: rellena MEASURED_PATHS con los directorios que ocupa el daemon
resolve_paths() {
    local docker_root driver_status
    # Sin daemon accesible no tiene sentido medir ni limpiar: fallar en vez de adivinar.
    docker_root=$(docker info -f '{{.DockerRootDir}}' 2>/dev/null) ||
        die "No se puede contactar con el daemon Docker"
    [[ -d $docker_root ]] || die "No se encuentra el directorio de Docker en $docker_root"
    MEASURED_PATHS=("$docker_root")

    driver_status=$(docker info -f '{{json .DriverStatus}}' 2>/dev/null) || true
    if [[ $driver_status == *io.containerd.snapshotter* && -d /var/lib/containerd ]]; then
        MEASURED_PATHS+=(/var/lib/containerd)
    fi
    MEASURED_PATHS+=("${EXTRA_PATHS[@]}")
}

# get_used_kb: imprime el uso total en KiB de MEASURED_PATHS
get_used_kb() {
    local total
    # -x no entra en los montajes overlay de contenedores activos (evita contar
    # dos veces sus capas); du devuelve 1 si un fichero desaparece durante el
    # recorrido, lo cual es normal con Docker en marcha.
    total=$(du -skxc "${MEASURED_PATHS[@]}" 2>/dev/null | awk 'END {print $1}') || true
    [[ $total =~ ^[0-9]+$ ]] || die "No se pudo medir el uso de ${MEASURED_PATHS[*]}"
    echo "$total"
}

# kb_to_gb KIB: imprime el valor en GiB con dos decimales
kb_to_gb() {
    awk -v kb="$1" 'BEGIN {printf "%.2f", kb / 1048576}'
}

# run_prune CMD...: ejecuta una limpieza (o la muestra en dry-run) y registra lo liberado
run_prune() {
    if [[ $DRY_RUN == true ]]; then
        log info "[dry-run] $*"
        return 0
    fi
    local output reclaimed
    if ! output=$("$@" 2>&1); then
        log warning "Falló '$*': ${output##*$'\n'}"
        return 0
    fi
    # "docker builder prune" informa con "Total:", el resto con "reclaimed space".
    reclaimed=$(awk '/[Rr]eclaimed|^Total:/ {line = $0} END {print line}' <<<"$output")
    log info "$*: ${reclaimed:-sin cambios}"
}

# prune_safe: nivel 1, solo recursos sin uso con más antigüedad que MIN_AGE
prune_safe() {
    log info "Nivel 1: contenedores detenidos, redes, imágenes dangling y build cache (> ${MIN_AGE})."
    run_prune docker system prune -f --filter "until=${MIN_AGE}"
}

# prune_unused_images: nivel 2, toda la build cache y las imágenes sin contenedores
prune_unused_images() {
    log info "Nivel 2: toda la build cache y las imágenes sin contenedores."
    run_prune docker builder prune -af
    run_prune docker image prune -af
}

# truncate_large_logs: nivel 3, vacía los logs json-file mayores que LOG_MAX_MB
truncate_large_logs() {
    log info "Nivel 3: logs de contenedores mayores de ${LOG_MAX_MB} MiB."
    local -a ids
    local log_path size max_bytes=$((LOG_MAX_MB * 1024 * 1024))
    mapfile -t ids < <(docker ps -aq)
    ((${#ids[@]})) || return 0

    while IFS= read -r log_path; do
        [[ -n $log_path && -f $log_path ]] || continue
        size=$(stat -c %s -- "$log_path")
        ((size > max_bytes)) || continue
        if [[ $DRY_RUN == true ]]; then
            log info "[dry-run] truncate -s 0 $log_path ($((size / 1048576)) MiB)"
        elif truncate -s 0 -- "$log_path"; then
            log info "Log vaciado: $log_path ($((size / 1048576)) MiB)"
        else
            log warning "No se pudo vaciar $log_path"
        fi
    done < <(docker inspect -f '{{.LogPath}}' "${ids[@]}" 2>/dev/null)
}

# prune_orphan_volumes: nivel 4, volúmenes anónimos sin contenedores (borra datos)
prune_orphan_volumes() {
    log warning "Nivel 4: volúmenes anónimos sin uso."
    run_prune docker volume prune -f
}

main() {
    parse_args "$@"
    validate_config
    require_commands docker du awk stat truncate
    acquire_lock
    resolve_paths

    local limit_kb=$((LIMIT_GB * 1024 * 1024))
    local used_kb
    used_kb=$(get_used_kb)

    if ((used_kb <= limit_kb)); then
        if [[ -t 1 ]]; then
            echo "Uso de Docker: $(kb_to_gb "$used_kb") GiB / ${LIMIT_GB} GiB. Nada que hacer."
        fi
        exit 0
    fi

    log warning "Uso actual ($(kb_to_gb "$used_kb") GiB) supera el límite de ${LIMIT_GB} GiB en ${MEASURED_PATHS[*]}. Iniciando limpieza..."

    local -a steps=(prune_safe prune_unused_images)
    [[ $TRUNCATE_LOGS == false ]] || steps+=(truncate_large_logs)
    [[ $PRUNE_VOLUMES == false ]] || steps+=(prune_orphan_volumes)

    local step
    for step in "${steps[@]}"; do
        "$step"
        [[ $DRY_RUN == false ]] || continue
        used_kb=$(get_used_kb)
        if ((used_kb <= limit_kb)); then
            log notice "Limpieza completada tras ${step}. Nuevo uso: $(kb_to_gb "$used_kb") GiB."
            exit 0
        fi
    done

    if [[ $DRY_RUN == true ]]; then
        log info "[dry-run] Fin de la simulación; no se ha borrado nada."
    else
        log err "Tras todos los niveles el uso sigue en $(kb_to_gb "$used_kb") GiB (límite ${LIMIT_GB} GiB). Revisa volúmenes, logs y contenedores activos."
    fi
    exit 2
}

main "$@"
