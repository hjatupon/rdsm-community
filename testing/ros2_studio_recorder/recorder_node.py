#!/usr/bin/env python3
"""
ros2_studio_recorder — ROS 2 node that wraps ros2 bag record behind std_srvs/Trigger.

Protocol (all std_srvs/Trigger):
  start:   Set parameters ros2_studio_recorder/recorder_topics (string array) and
           ros2_studio_recorder/recorder_filename (string) via the node's built-in
           /ros2_studio_recorder/set_parameters service, then call:
           /ros2_studio_recorder/start → response.message = "Recording N topics..."

  stop:    /ros2_studio_recorder/stop → response.message = JSON (file_path, file_size, message_count)

  status:  /ros2_studio_recorder/status → response.message = JSON (is_recording, elapsed_sec, file_size, file_path)

HTTP file server (port 9091 by default):
  List:    GET /list → JSON array of bag files (name, size, mtime)
  Download: GET /download/<filename> → binary file stream
"""
import json
import os
import signal
import subprocess
import threading
import time
import urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

import rclpy
from rclpy.node import Node
from std_srvs.srv import Trigger

BAGS_DIR = Path("/sim-bot/bags")


class BagFileHTTPHandler(BaseHTTPRequestHandler):
    """Serves bag files from BAGS_DIR over HTTP.

    Endpoints:
      GET /list            → JSON array of {name, size, mtime}
      GET /download/<name> → file bytes (streamed), resolves ros2 bag directories
    """

    def do_GET(self):
        if self.path == "/list":
            self._serve_list()
        elif self.path.startswith("/download/"):
            raw = self.path[len("/download/"):]
            filename = urllib.parse.unquote(raw)
            # Reject path traversal
            if ".." in filename or filename.startswith("/"):
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b"Bad request")
                return
            target = BAGS_DIR / filename
            if target.is_dir():
                # ros2 bag record creates a directory; serve the .mcap data file inside
                mcap_files = sorted(target.glob("*.mcap"))
                if mcap_files:
                    self._stream_file(mcap_files[0])
                else:
                    self.send_response(404)
                    self.end_headers()
                    self.wfile.write(b"No MCAP file found in bag directory")
            elif target.is_file():
                self._stream_file(target)
            else:
                self.send_response(404)
                self.end_headers()
                self.wfile.write(b"Not found")
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not found")

    def _stream_file(self, path: Path) -> None:
        """Stream a file with Content-Length so URLSession can report download progress."""
        try:
            file_size = path.stat().st_size
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(file_size))
            self.send_header("Content-Disposition", f'attachment; filename="{path.name}"')
            self.end_headers()
            with open(path, "rb") as fh:
                while True:
                    chunk = fh.read(65536)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
        except (BrokenPipeError, ConnectionResetError):
            pass  # client disconnected mid-download

    def _serve_list(self):
        entries = []
        for f in BAGS_DIR.iterdir():
            if f.is_file() and f.suffix == ".mcap":
                entries.append({
                    "name": f.name,
                    "size": f.stat().st_size,
                    "mtime": f.stat().st_mtime,
                })
            elif f.is_dir():
                # ros2 bag record -o <path> creates a directory; data file is <name>_0.mcap
                mcap_files = sorted(f.glob("*.mcap"))
                if mcap_files:
                    total_size = sum(p.stat().st_size for p in f.rglob("*") if p.is_file())
                    entries.append({
                        "name": f.name,
                        "size": total_size,
                        "mtime": mcap_files[0].stat().st_mtime,
                    })
        entries.sort(key=lambda e: e["mtime"], reverse=True)
        body = json.dumps(entries).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        """Suppress HTTP request logs (too noisy)."""
        pass


class RecorderNode(Node):
    def __init__(self):
        super().__init__("ros2_studio_recorder")
        self._bag_process: subprocess.Popen | None = None
        self._bag_path: Path | None = None
        self._start_time: float = 0.0
        self._topics: list[str] = []
        self._http_server: HTTPServer | None = None
        self._http_thread: threading.Thread | None = None

        # Declare parameters — can be set via /ros2_studio_recorder/set_parameters
        self.declare_parameter("recorder_topics", [""])
        self.declare_parameter("recorder_filename", "")
        self.declare_parameter("http_port", 9091)

        BAGS_DIR.mkdir(parents=True, exist_ok=True)

        self.srv_start = self.create_service(Trigger, "/ros2_studio/recorder/start", self._handle_start)
        self.srv_stop = self.create_service(Trigger, "/ros2_studio/recorder/stop", self._handle_stop)
        self.srv_status = self.create_service(Trigger, "/ros2_studio/recorder/status", self._handle_status)
        self.get_logger().info("ros2_studio_recorder ready — set parameters then call start")

        # Start HTTP file server on a daemon thread
        self._start_http_server()

    def _start_http_server(self) -> None:
        port = self.get_parameter("http_port").value
        try:
            self._http_server = HTTPServer(("0.0.0.0", port), BagFileHTTPHandler)
            self._http_thread = threading.Thread(
                target=self._http_server.serve_forever,
                daemon=True,
            )
            self._http_thread.start()
            self.get_logger().info(f"HTTP file server listening on port {port}")
        except Exception as e:
            self.get_logger().warn(f"Failed to start HTTP file server on port {port}: {e}")

    def _stop_http_server(self) -> None:
        if self._http_server:
            self._http_server.shutdown()
            self._http_server = None
            self._http_thread = None

    def _get_topics(self) -> list[str]:
        raw = self.get_parameter("recorder_topics").value
        if isinstance(raw, list):
            return [t for t in raw if t]
        if isinstance(raw, str):
            return [raw] if raw else []
        return []

    def _get_filename(self) -> str:
        raw = self.get_parameter("recorder_filename").value
        if isinstance(raw, str) and raw:
            return raw if raw.endswith(".mcap") else raw + ".mcap"
        return ""

    def _handle_start(self, request, response):
        if self._bag_process is not None:
            response.success = False
            response.message = "Already recording"
            return response

        topics = self._get_topics()
        if not topics:
            response.success = False
            response.message = "No topics set. Set recorder_topics parameter first."
            return response

        filename = self._get_filename()
        if not filename:
            filename = f"recording-{time.strftime('%Y-%m-%d_%H-%M-%S')}.mcap"

        bag_dir = BAGS_DIR / filename
        self._bag_path = bag_dir
        self._topics = topics
        self._start_time = time.time()

        cmd = ["ros2", "bag", "record", "--storage", "mcap", "-o", str(bag_dir)] + topics
        self.get_logger().info(f"Starting: {' '.join(cmd)}")

        try:
            self._bag_process = subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                preexec_fn=os.setsid,
            )
            response.success = True
            response.message = f"Recording {len(topics)} topics to {bag_dir}"
        except Exception as e:
            self._bag_process = None
            self._bag_path = None
            response.success = False
            response.message = f"Failed to start: {e}"

        return response

    def _handle_stop(self, request, response):
        if self._bag_process is None:
            response.success = False
            response.message = json.dumps({"error": "Not recording"})
            return response

        # Send SIGINT for clean shutdown — ros2 bag record writes metadata.yaml
        try:
            os.killpg(os.getpgid(self._bag_process.pid), signal.SIGINT)
        except ProcessLookupError:
            pass

        try:
            self._bag_process.wait(timeout=10.0)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(os.getpgid(self._bag_process.pid), signal.SIGKILL)
            except ProcessLookupError:
                pass
            self._bag_process.wait()

        file_size = 0
        message_count = 0
        if self._bag_path and self._bag_path.exists():
            file_size = sum(f.stat().st_size for f in self._bag_path.rglob("*") if f.is_file())
            meta_file = self._bag_path / "metadata.yaml"
            if meta_file.exists():
                try:
                    import yaml
                    with open(meta_file) as fh:
                        meta = yaml.safe_load(fh)
                    message_count = meta.get("rosbag2_bagfile_information", {}).get("message_count", 0)
                except Exception:
                    pass

        result = {
            "file_path": str(self._bag_path) if self._bag_path else "",
            "file_size": file_size,
            "message_count": message_count,
        }
        response.success = True
        response.message = json.dumps(result)

        self._bag_process = None
        self._bag_path = None
        return response

    def _handle_status(self, request, response):
        if self._bag_process is None:
            result = {"is_recording": False, "elapsed_sec": 0, "message_count": 0, "file_size": 0, "file_path": None}
        else:
            elapsed = int(time.time() - self._start_time)
            file_size = 0
            if self._bag_path and self._bag_path.exists():
                file_size = sum(f.stat().st_size for f in self._bag_path.rglob("*") if f.is_file())
            result = {
                "is_recording": True,
                "elapsed_sec": elapsed,
                "message_count": 0,
                "file_size": file_size,
                "file_path": str(self._bag_path) if self._bag_path else None,
            }
        response.success = True
        response.message = json.dumps(result)
        return response


def main(args=None):
    rclpy.init(args=args)
    node = RecorderNode()
    try:
        rclpy.spin(node)
    finally:
        node._stop_http_server()
        node.destroy_node()
    rclpy.shutdown()


if __name__ == "__main__":
    main()
