"""离线验证参数选择和模型探针协议；本地桩不代表真实网关实测。"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[1]


class EntryPointTests(unittest.TestCase):
    def test_selection_without_loading_environment(self):
        with tempfile.NamedTemporaryFile(mode="w") as env_file:
            env_file.write("exit 91\n")
            env_file.flush()
            env = dict(os.environ, XBD_ENV_FILE=env_file.name)
            steps = sorted((ROOT / "steps").glob("step-*.sh"))
            self.assertEqual(len(steps), 13)
            for number, step in enumerate(steps, 1):
                self.assertTrue(step.name.startswith(f"step-{number:02d}-"))
                self.assertTrue(step.with_suffix(".md").exists())
                for selector in {str(number), f"{number:02d}"}:
                    result = subprocess.run(["bash", str(ROOT / "run-all.sh"), "--only", selector, "--dry-run"],
                                            env=env, capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn(step.stem, result.stdout)
                    self.assertEqual(result.stdout.count("▶"), 1)
            for args, count in [(["--dry-run"], 13), (["--from", "09", "--dry-run"], 5),
                                (["--from", "11", "--dry-run"], 3), (["--list"], 13)]:
                result = subprocess.run(["bash", str(ROOT / "run-all.sh"), *args],
                                        env=env, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(len(result.stdout.splitlines()), count)
            invalid = [["--from"], ["--only", "14"], ["--only", "0"], ["--only", "A"],
                       ["--only", "009"], ["--from", "1", "--only", "11"],
                       ["--only", "9", "--only", "10"], ["--with-ext"]]
            for args in invalid:
                result = subprocess.run(["bash", str(ROOT / "run-all.sh"), *args],
                                        env=env, capture_output=True, timeout=10)
                self.assertEqual(result.returncode, 2, args)

    def test_model_probe_contracts(self):
        cases = [
            ("--probe-text", 200, {"choices": [{"message": {"content": "XBD_MODEL_OK"}}]}, 0),
            ("--probe-text", 200, {"error": "not a completion"}, 1),
            ("--probe-text", 403, {"error": "quota exhausted"}, 1),
            ("--probe-tools", 200, {"choices": [{"message": {"tool_calls": [{"function": {
                "name": "demo_echo", "arguments": '{"text":"XBD_TOOL_OK"}'}}]}}]}, 0),
            ("--probe-tools", 200, {"choices": [{"message": {"content": "I called a tool"}}]}, 1),
            ("--probe-tools", 200, {"choices": [{"message": {"tool_calls": [{"function": {
                "name": "demo_echo", "arguments": "invalid json"}}]}}]}, 1),
        ]
        for mode, status, response, expected in cases:
            requests = []

            class Handler(BaseHTTPRequestHandler):
                def do_POST(self):
                    body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                    requests.append((self.path, self.headers.get("Authorization"), body))
                    self.send_response(status)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps(response).encode())

                def log_message(self, *_args):
                    pass

            server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                with tempfile.NamedTemporaryFile() as env_file:
                    env = dict(os.environ, XBD_ENV_FILE=env_file.name,
                               XBD_MODEL_BASE_URL=f"http://127.0.0.1:{server.server_port}",
                               XBD_MODEL_ENDPOINT_PATH="/v1/chat/completions",
                               XBD_MODEL_API_KEY="local-test-placeholder", XBD_MODEL_NAME="test-model")
                    result = subprocess.run(["bash", str(ROOT / "steps/step-13-model-channel.sh"), mode],
                                            env=env, capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode, expected, (mode, result.stdout, result.stderr))
                    self.assertEqual(result.stderr, "")
                    if status != 200:
                        self.assertIn(f"HTTP {status}", result.stdout)
                    self.assertEqual(len(requests), 1)
                    path, auth, body = requests[0]
                    self.assertEqual(path, "/v1/chat/completions")
                    self.assertEqual(auth, "Bearer local-test-placeholder")
                    self.assertEqual(body["model"], "test-model")
                    self.assertFalse(body["stream"])
                    if mode == "--probe-tools":
                        self.assertEqual(body["tool_choice"]["function"]["name"], "demo_echo")
                    self.assertNotIn("local-test-placeholder", result.stdout + result.stderr)
            finally:
                server.shutdown()
                server.server_close()
                thread.join()


if __name__ == "__main__":
    unittest.main()
