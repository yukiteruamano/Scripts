#!/usr/bin/env python3

import json
import sys
import argparse
import ipaddress
import urllib.request
import urllib.error
import time
from collections import defaultdict


def load_config(config_path):
    """
    Carga la configuración desde un archivo JSON.

    Args:
        config_path (str): Ruta al archivo de configuración JSON.

    Returns:
        dict: Configuración cargada desde el archivo.

    Raises:
        SystemExit: Si el archivo no se encuentra o no es un JSON válido.
    """
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            config = json.load(f)
        # Validar campos obligatorios
        required_fields = ["api_token", "account_id", "list_id"]
        missing_fields = [field for field in required_fields if field not in config]
        if missing_fields:
            print(
                f"Error: Faltan campos obligatorios en el archivo de configuración: {', '.join(missing_fields)}"
            )
            sys.exit(1)
        return config
    except FileNotFoundError:
        print(f"Error: No se encontró el archivo de configuración en {config_path}")
        sys.exit(1)
    except json.JSONDecodeError:
        print(f"Error: El archivo de configuración {config_path} no es un JSON válido.")
        sys.exit(1)
    except Exception as e:
        print(f"Error inesperado al cargar la configuración: {e}")
        sys.exit(1)


def get_ip_info(ip_address, api_token=None):
    """
    Obtiene información de geolocalización y ASN para una IP usando ipinfo.io

    Args:
        ip_address (str): Dirección IP a consultar
        api_token (str, optional): Token de API para ipinfo.io (opcional pero recomendado)

    Returns:
        dict: Información de la IP incluyendo país y ASN
    """
    url = f"https://ipinfo.io/{ip_address}/json"
    headers = {}

    if api_token:
        headers["Authorization"] = f"Bearer {api_token}"

    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode("utf-8"))
            # Asegurarnos de que los campos clave estén presentes
            if "country" not in data:
                data["country"] = ""
            if "org" not in data:
                data["org"] = ""
            return data
    except urllib.error.HTTPError as e:
        print(f"Error al consultar ipinfo.io para {ip_address}: {e.code} - {e.reason}")
        return {"country": "", "org": ""}
    except Exception as e:
        print(f"Error inesperado al consultar ipinfo.io para {ip_address}: {e}")
        return {"country": "", "org": ""}


def sync_with_cloudflare(ips, config):
    """
    Sincroniza la lista de IPs con una IP List de Cloudflare WAF.

    Args:
        ips (set): Conjunto de IPs a sincronizar.
        config (dict): Configuración cargada desde el archivo JSON.

    Returns:
        None
    """
    api_token = config.get("api_token")
    account_id = config.get("account_id")
    list_id = config.get("list_id")

    if not all([api_token, account_id, list_id]):
        print(
            "Error: Faltan campos obligatorios en el archivo de configuración (api_token, account_id, list_id)."
        )
        return

    url = f"https://api.cloudflare.com/client/v4/accounts/{account_id}/rules/lists/{list_id}/items"

    # Cloudflare permite hasta 1000 items por petición
    batch_size = 1000
    ip_list = list(ips)
    total_batches = (len(ip_list) + batch_size - 1) // batch_size

    print(f"\nIniciando sincronización con Cloudflare...")
    print(f"Total de IPs a sincronizar: {len(ip_list)}")
    print(f"Número de lotes: {total_batches}\n")

    for i in range(0, len(ip_list), batch_size):
        batch = ip_list[i : i + batch_size]
        payload = [
            {"ip": ip, "comment": f"Blocked by script {time.strftime('%Y-%m-%d')}"}
            for ip in batch
        ]

        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {api_token}",
                "Content-Type": "application/json",
            },
            method="POST",
        )

        try:
            with urllib.request.urlopen(req) as response:
                result = json.loads(response.read().decode("utf-8"))
                if result.get("success"):
                    print(
                        f"✓ Lote {i // batch_size + 1}/{total_batches} enviado con éxito ({len(batch)} IPs)."
                    )
                else:
                    print(
                        f"✗ Error en el lote {i // batch_size + 1}/{total_batches}: {result.get('errors')}"
                    )
        except urllib.error.HTTPError as e:
            error_body = e.read().decode("utf-8")
            print(
                f"✗ Error HTTP al sincronizar con Cloudflare (Lote {i // batch_size + 1}/{total_batches}): {e.code} - {error_body}"
            )
        except Exception as e:
            print(f"✗ Error inesperado al sincronizar con Cloudflare: {e}")

    print(f"\nSincronización completada. Total de IPs procesadas: {len(ip_list)}")


def main():
    # Configuración de argumentos de línea de comandos
    parser = argparse.ArgumentParser(
        description="Filtra IPs bloqueadas desde un JSON y las sincroniza opcionalmente con Cloudflare WAF."
    )
    parser.add_argument("input_json", help="Ruta al archivo JSON de entrada")
    parser.add_argument("output_txt", help="Ruta al archivo de texto de salida")
    parser.add_argument(
        "--upload",
        action="store_true",
        help="Sincroniza las IPs bloqueadas con Cloudflare WAF",
    )
    parser.add_argument(
        "--config",
        default="cf_config.json",
        help="Ruta al archivo de configuración JSON (por defecto: cf_config.json)",
    )
    parser.add_argument(
        "--exclude-countries",
        nargs="+",
        default=[],
        help="Códigos de países para excluir (ej: ES FR DE)",
    )
    parser.add_argument(
        "--exclude-asns",
        nargs="+",
        default=[],
        help="Números ASN para excluir (ej: AS1234 AS5678)",
    )
    parser.add_argument(
        "--include-countries",
        nargs="+",
        default=[],
        help="Códigos de países para incluir (ej: CN RU)",
    )
    parser.add_argument(
        "--include-asns",
        nargs="+",
        default=[],
        help="Números ASN para incluir (ej: AS9999)",
    )
    args = parser.parse_args()

    # IPs específicas a excluir (como localhost, etc.)
    excluded_specific_ips = {"146.70.187.54", "::1"}

    # Cargar configuración de países y ASNs desde el archivo de configuración
    try:
        config = load_config(args.config)
        ipinfo_token = config.get("ipinfo_token")
        country_exclusions = config.get("exclude_countries", [])
        country_inclusions = config.get("include_countries", [])
        asn_exclusions = config.get("exclude_asns", [])
        asn_inclusions = config.get("include_asns", [])
    except Exception:
        # Si no se puede cargar la configuración, usar valores por defecto
        ipinfo_token = None
        country_exclusions = []
        country_inclusions = []
        asn_exclusions = []
        asn_inclusions = []

    # Combinar con argumentos de línea de comandos
    country_exclusions.extend(args.exclude_countries)
    country_inclusions.extend(args.include_countries)
    asn_exclusions.extend(args.exclude_asns)
    asn_inclusions.extend(args.include_asns)

    try:
        with open(args.input_json, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        print(f"✗ Error al leer el archivo JSON: {e}")
        sys.exit(1)

    if isinstance(data, dict):
        logs = [data]
    else:
        logs = data

    # Usamos un set para evitar duplicados automáticamente
    extracted_ips = set()
    ip_stats = defaultdict(int)
    country_stats = defaultdict(int)
    asn_stats = defaultdict(int)

    for entry in logs:
        if entry.get("action") == "block":
            ip_str = entry.get("clientIP")
            if not ip_str or ip_str in excluded_specific_ips:
                continue

            try:
                ip_obj = ipaddress.ip_address(ip_str)

                # Verificar si es una IP específica a excluir
                if ip_str in excluded_specific_ips:
                    continue

                # Verificar filtros de país y ASN si hay configuración
                if (
                    country_exclusions
                    or country_inclusions
                    or asn_exclusions
                    or asn_inclusions
                ):
                    ip_info = get_ip_info(ip_str, ipinfo_token)
                    country_code = ip_info.get("country", "").upper()
                    asn = (
                        ip_info.get("org", "").split(" ")[0]
                        if ip_info.get("org")
                        else ""
                    )

                    # Aplicar filtros de exclusión
                    if country_code in country_exclusions:
                        continue
                    if asn in asn_exclusions:
                        continue

                    # Aplicar filtros de inclusión (si hay inclusiones, solo permitir esas)
                    if country_inclusions and country_code not in country_inclusions:
                        continue
                    if asn_inclusions and asn not in asn_inclusions:
                        continue

                extracted_ips.add(ip_str)
                ip_stats[ip_str] += 1
            except ValueError:
                continue

    # Mostrar estadísticas
    print(f"\n📊 Estadísticas de procesamiento:")
    print(f"  Total de entradas procesadas: {len(logs)}")
    print(f"  IPs únicas encontradas: {len(extracted_ips)}")

    # Mostrar configuración de filtros aplicados
    if country_exclusions or country_inclusions or asn_exclusions or asn_inclusions:
        print(f"\n🌍 Filtros aplicados:")
        if country_exclusions:
            print(f"  Países excluidos: {', '.join(country_exclusions)}")
        if country_inclusions:
            print(f"  Países incluidos: {', '.join(country_inclusions)}")
        if asn_exclusions:
            print(f"  ASNs excluidos: {', '.join(asn_exclusions)}")
        if asn_inclusions:
            print(f"  ASNs incluidos: {', '.join(asn_inclusions)}")

    print(f"\n📈 Top 10 IPs más frecuentes:")
    for ip, count in sorted(ip_stats.items(), key=lambda x: x[1], reverse=True)[:10]:
        print(f"    {ip}: {count} ocurrencias")

    try:
        with open(args.output_txt, "w", encoding="utf-8") as f:
            # Escribimos las IPs únicas (opcionalmente ordenadas)
            for ip in sorted(extracted_ips):
                f.write(f"{ip}\n")
        print(
            f"\n✓ Proceso completado. Se han guardado {len(extracted_ips)} IPs únicas en {args.output_txt}"
        )

        # Sincronización con Cloudflare
        if args.upload and extracted_ips:
            print(
                f"\n🔄 Iniciando sincronización de {len(extracted_ips)} IPs con Cloudflare..."
            )
            config = load_config(args.config)
            sync_with_cloudflare(extracted_ips, config)

    except Exception as e:
        print(f"\n✗ Error en la fase final del proceso: {e}")
        sys.exit(1)


if __name__ == "__main__":
    # Mostrar banner
    print("""
    🔒 Cloudflare IP Blocklist Processor
    =====================================
    Procesa logs de bloqueo y sincroniza con Cloudflare WAF
    """)
    main()
