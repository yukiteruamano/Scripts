import re
from collections.abc import Callable


class ProgressHandler:
    def __init__(self, duration_callback: Callable[[float], None] | None = None):
        self.duration_callback = duration_callback
        self.total_duration_ms: float = 0
        self.progress_data: dict[str, str] = {}

    def parse_line(self, line: str):
        # 1. Look for duration in the header
        # Format: Duration: 00:00:05.12, ...
        if "Duration:" in line:
            match = re.search(r"Duration:\s+(\d+):(\d+):(\d+).(\d+)", line)
            if match:
                h, m, s, fract = match.groups()
                # Correct calculation regardless of fraction length
                # Convert fraction to milliseconds (e.g. .12 -> 120ms, .123 -> 123ms, .1 -> 100ms)
                ms_val = int(fract.ljust(3, "0")[:3])
                self.total_duration_ms = (
                    int(h) * 3600 + int(m) * 60 + int(s)
                ) * 1000 + ms_val
                if self.duration_callback:
                    self.duration_callback(self.total_duration_ms)

        # 2. Parse key-value progress (from -progress pipe:1)
        if "=" in line:
            parts = line.split("=", 1)
            if len(parts) == 2:
                key, value = parts
                self.progress_data[key.strip()] = value.strip()

    @property
    def percentage(self) -> float:
        if self.total_duration_ms > 0 and "out_time_ms" in self.progress_data:
            try:
                out_time_ms = int(self.progress_data["out_time_ms"])
                # We divide by 1000 because out_time_ms is actually in microseconds for some ffmpeg versions
                # despite the name, or it might be in milliseconds.
                # Actually, in most modern ffmpeg -progress output, out_time_ms is microseconds.

                # Check if it looks like microseconds (large value compared to duration)
                actual_out_ms = (
                    out_time_ms / 1000.0
                    if out_time_ms > self.total_duration_ms * 10
                    else out_time_ms
                )

                return min(100.0, (actual_out_ms / self.total_duration_ms) * 100)
            except ValueError, KeyError:
                pass
        return 0.0

    @property
    def elapsed_time(self) -> str:
        if "out_time" in self.progress_data:
            return self.progress_data["out_time"].split(".")[0]
        return "00:00:00"

    @property
    def speed(self) -> str:
        return self.progress_data.get("speed", "N/A")

    @property
    def fps(self) -> str:
        return self.progress_data.get("fps", "0")
