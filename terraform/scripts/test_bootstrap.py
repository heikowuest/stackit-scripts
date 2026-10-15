import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, patch

spec = importlib.util.spec_from_file_location("bootstrap", Path(__file__).with_name("bootstrap.py"))
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)

class BootstrapTests(unittest.TestCase):
    def test_raw_disk_has_yaml_at_zero_and_newline_padding(self):
        path = MagicMock()
        stream = path.open.return_value.__enter__.return_value
        text = "cluster:\n  domainname: example.test\n"
        with patch.object(b.os, "chmod"):
            b.write_raw(path, text)
        writes = stream.write.call_args_list
        self.assertEqual(writes[0].args[0], text.encode("ascii"))
        self.assertEqual(writes[1].args[0], b"\n" * (2 * 1024 * 1024))
        stream.truncate.assert_called_once_with(1024 ** 3)

    def test_yaml_static_address_and_escaping(self):
        text = b.yaml_config(
            {"ip": "192.0.2.7", "prefix": 24, "gateway": "192.0.2.1",
             "dns": ["192.0.2.53", "192.0.2.54"]},
            "anvil", "example.test", ["ntp.example.test"], 'a": #\\!秘密', "eth0")
        self.assertIn('192.0.2.7/24', text)
        self.assertIn("dhcp: false", text)
        self.assertIn('    - "192.0.2.53"\n    - "192.0.2.54"', text)
        text.encode("ascii")
        self.assertNotIn("秘密", text)

    def test_dsx_yaml_joins_anvil_without_registering_config_disk(self):
        text = b.yaml_config(
            {"ip": "192.0.2.8", "prefix": 24, "gateway": "192.0.2.1",
             "dns": ["192.0.2.53"], "anvil_ip": "192.0.2.7"},
            "dsx", "example.test", ["ntp.example.test"], "test" + "!", "eth0",
            role="dsx")
        self.assertIn('metadata:\n    ips:\n      - "192.0.2.7"', text)
        self.assertIn('192.0.2.8/24', text)
        self.assertIn("add_node: true", text)
        self.assertIn("add_volumes: false", text)
        self.assertIn("- storage", text)
        self.assertIn("- portal", text)
        self.assertNotIn("ha_mode", text)

    def test_dsx_requires_anvil_address(self):
        with self.assertRaises(KeyError):
            b.yaml_config(
                {"ip": "192.0.2.8", "prefix": 24, "gateway": "192.0.2.1",
                 "dns": ["192.0.2.53"]},
                "dsx", "example.test", ["ntp.example.test"], "test" + "!", "eth0",
                role="dsx")

    def test_invalid_network_rejected(self):
        with self.assertRaises(ValueError):
            b.yaml_config({"ip": "bad", "prefix": 24, "gateway": "192.0.2.1", "dns": []},
                          "a", "b", ["c"], "d!", "eth0")

    def test_create_includes_both_disks_before_import(self):
        data = dict(project_id="p", region="r", name="n", machine_type="g1a.16d",
                    availability_zone="r-1",
                    nic_id="nic", boot_id="boot", metadata_id="meta", config_id="cfg")
        events = []
        def run(args, capture=False):
            events.append(args)
            return "[]" if "list" in args else json.dumps({"id": "server"})
        def tf(tool, *args, capture=False):
            events.append(list(args))
            return "" if args[:2] == ("state", "list") else None
        with patch.object(b, "output", return_value=data), patch.object(b, "run", side_effect=run), patch.object(b, "tf", side_effect=tf):
            b.create(SimpleNamespace(tool="terraform", resume_server_id=None))
        create = next(e for e in events if "create" in e)
        self.assertEqual(create[create.index("--volumes") + 1], "cfg,meta")
        self.assertEqual(create[create.index("--agent-provisioning-policy") + 1], "NEVER")
        self.assertEqual(len([e for e in events if e[0] == "import"]), 3)

    def test_existing_name_requires_explicit_resume(self):
        data = dict(project_id="p", region="r", name="n", machine_type="g1a.16d",
                    availability_zone="r-1",
                    nic_id="nic", boot_id="boot", metadata_id="meta", config_id="cfg")
        with patch.object(b, "output", return_value=data), patch.object(b, "run", return_value='[{"name":"n","id":"s"}]'):
            with self.assertRaises(ValueError):
                b.create(SimpleNamespace(tool="terraform", resume_server_id=None))

    def test_dsx_create_imports_dsx_and_data_attachment(self):
        data = dict(project_id="p", region="r", name="dsx", machine_type="g1a.16d",
                    availability_zone="r-1", role="dsx",
                    nic_id="nic", boot_id="boot", metadata_id="data", config_id="cfg")
        calls = []
        def run(args, capture=False):
            return "[]" if "list" in args else json.dumps({"id": "dsx-server"})
        def tf(tool, *args, capture=False):
            calls.append(args)
            return "" if args[:2] == ("state", "list") else None
        with patch.object(b, "output", return_value=data), patch.object(b, "run", side_effect=run), patch.object(b, "tf", side_effect=tf):
            b.create(SimpleNamespace(tool="terraform", role="dsx", resume_server_id=None))
        imports = [c[1] for c in calls if c[0] == "import"]
        self.assertEqual(imports, ["stackit_server.dsx", "stackit_server_volume_attach.config",
                                  "stackit_server_volume_attach.data"])

    def test_dsx_api_failure_does_not_write_config_disk(self):
        args = SimpleNamespace(tool="terraform", role="dsx")
        with patch.object(b.os, "name", "posix"), patch.object(b.shutil, "which", return_value="qemu-img"), patch.object(b, "output", return_value={"role":"dsx", "anvil_ip":"192.0.2.7"}), patch.object(b.getpass, "getpass", return_value="test" + "!"), patch.object(b.urllib.request, "urlopen", side_effect=OSError("API unreachable")), patch.object(b, "write_raw") as writer:
            with self.assertRaises(OSError):
                b.prepare(args)
            writer.assert_not_called()

    def test_wrong_state_role_rejected_before_cli(self):
        with patch.object(b, "output", return_value={"role":"anvil"}), patch.object(b, "run") as runner:
            with self.assertRaises(ValueError):
                b.create(SimpleNamespace(tool="terraform", role="dsx"))
            runner.assert_not_called()

if __name__ == "__main__":
    unittest.main()
