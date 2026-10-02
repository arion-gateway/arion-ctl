#!/usr/bin/env python3
"""Exercise an installed arionctl release and real Arion proxy without Docker."""
import argparse
import json
import os
from pathlib import Path
import pty
import select
import socket
import subprocess
import tempfile
import threading
import time
import urllib.request


def port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def eventually(fn, timeout=30):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        try:
            result = fn()
            if result:
                return result
        except Exception as error:
            last = error
        time.sleep(.15)
    raise AssertionError(f'timed out: {last}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--release', required=True, type=Path)
    parser.add_argument('--proxy', required=True, type=Path)
    args = parser.parse_args()
    release, proxy = args.release.resolve(), args.proxy.resolve()
    with tempfile.TemporaryDirectory(prefix='arion-smoke-') as tmp:
        root = Path(tmp)
        ads, http, mcp = port(), port(), port()
        env = dict(os.environ, ARION_CTL_PORT=str(ads), ARION_CTL_STATE_DIR=str(root / 'state'),
                   RELEASE_NODE=f'arion_smoke_{os.getpid()}', ERL_FLAGS='+S 2:2')
        ctl = release / 'bin/arionctl'
        def command(*arguments, ok=True):
            result = subprocess.run([str(ctl), *arguments], env=env, text=True, capture_output=True, timeout=30)
            if ok and result.returncode:
                raise AssertionError(result.stdout + result.stderr)
            if not ok:
                assert result.returncode != 0, result.stdout
            return result.stdout
        ctl_log = (root / 'ctl.log').open('w+')
        proxy_log = (root / 'proxy.log').open('w+')
        server = subprocess.Popen([str(ctl), 'serve'], env=env, stdout=ctl_log, stderr=subprocess.STDOUT)
        dataplane = None
        try:
            eventually(lambda: socket.create_connection(('127.0.0.1', ads), timeout=.2).close() is None)
            def listener(name, listen_port, body, mcp_filter=False):
                filters = []
                if mcp_filter:
                    filters.append({'name': 'arion.filters.http.mcp', 'typedConfig': {
                        '@type': 'type.googleapis.com/arion.extensions.filters.http.mcp.mcp_gateway.v3.McpGateway',
                        'serverInfo': {'name': 'arion-smoke', 'version': '1'}, 'toolsMode': {}}})
                filters.append({'name': 'envoy.filters.http.router', 'typedConfig': {
                    '@type': 'type.googleapis.com/envoy.extensions.filters.http.router.v3.Router'}})
                return {'apiVersion': 'ctl.arion.io/v1alpha1', 'kind': 'Listener',
                        'metadata': {'name': name, 'fleet': 'arion'}, 'spec': {
                            'address': {'socketAddress': {'address': '127.0.0.1', 'portValue': listen_port}},
                            'filterChains': [{'name': name, 'filters': [{'name': 'http', 'typedConfig': {
                                '@type': 'type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager',
                                'statPrefix': 'smoke', 'codecType': 'HTTP1', 'httpFilters': filters,
                                'routeConfig': {'name': 'routes', 'virtualHosts': [{'name': 'all', 'domains': ['*'],
                                    'routes': [{'match': {'prefix': '/'}, 'directResponse': {
                                        'status': 200, 'body': {'inlineString': body}}}]}]}
                            }}]}]}}
            manifest = root / 'resources.yaml'
            docs = [listener('http', http, 'before'), listener('mcp', mcp, 'mcp', True)]
            manifest.write_text('\n---\n'.join(json.dumps(d) for d in docs))
            command('validate', '-f', str(manifest))
            command('apply', '-f', str(manifest))
            assert len(json.loads(command('get'))) == 2
            bootstrap = {'runtime': {'num_cpus': 1, 'num_runtimes': 1}, 'logging': {'log_level': 'warn'},
                'envoy_bootstrap': {'node': {'id': 'smoke', 'cluster': 'arion'}, 'dynamic_resources': {
                    'ads_config': {'grpc_services': [{'envoy_grpc': {'cluster_name': 'xds'}}]}},
                    'static_resources': {'clusters': [{'name': 'xds', 'type': 'STATIC', 'connect_timeout': '1s',
                        'typed_extension_protocol_options': {'envoy.extensions.upstreams.http.v3.HttpProtocolOptions': {
                            '@type': 'type.googleapis.com/envoy.extensions.upstreams.http.v3.HttpProtocolOptions',
                            'explicit_http_config': {'http2_protocol_options': {}}}},
                        'load_assignment': {'cluster_name': 'xds', 'endpoints': [{'lb_endpoints': [{'endpoint': {
                            'address': {'socket_address': {'address': '127.0.0.1', 'port_value': ads}}}}]}]}}]}}}
            config = root / 'bootstrap.json'
            config.write_text(json.dumps(bootstrap))
            dataplane = subprocess.Popen([str(proxy), '--config', str(config)], stdout=proxy_log, stderr=subprocess.STDOUT)
            def get_body():
                with urllib.request.urlopen(f'http://127.0.0.1:{http}/', timeout=1) as response:
                    return response.read().decode()
            eventually(lambda: get_body() == 'before')
            def steady(allowed, action):
                # Poll the HTTP listener while action(seen) runs: every request must succeed with an allowed body.
                seen, stop = [], threading.Event()
                def poll():
                    while not stop.is_set():
                        try: seen.append(get_body())
                        except Exception as error: seen.append(repr(error))
                        time.sleep(.02)
                poller = threading.Thread(target=poll)
                poller.start()
                try: action(seen)
                finally: stop.set(); poller.join()
                assert seen and set(seen) <= allowed, [body for body in seen if body not in allowed][:5]
                return len(seen)
            payload = {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {
                'protocolVersion': '2025-03-26', 'capabilities': {}, 'clientInfo': {'name': 'smoke', 'version': '1'}}}
            def initialize():
                req = urllib.request.Request(f'http://127.0.0.1:{mcp}/mcp', json.dumps(payload).encode(),
                    {'Content-Type': 'application/json', 'Accept': 'application/json, text/event-stream'})
                with urllib.request.urlopen(req, timeout=2) as response:
                    return json.loads(response.read())['result']['serverInfo']['name'] == 'arion-smoke'
            eventually(initialize)
            invalid = root / 'invalid.yaml'
            invalid.write_text('apiVersion: wrong\n')
            command('apply', '-f', str(invalid), ok=False)
            assert get_body() == 'before'
            docs[0] = listener('http', http, 'after')
            manifest.write_text('\n---\n'.join(json.dumps(d) for d in docs))
            command('apply', '-f', str(manifest))
            eventually(lambda: get_body() == 'after')
            command('status')
            # Kill the fleet process: the Store must repopulate it before the proxy's reconnect
            # replay could remove anything, and the already-connected proxy must keep receiving updates.
            def rpc(expression):
                result = subprocess.run([str(release / 'bin/arion_ctl'), 'rpc', expression], env=env,
                                        text=True, capture_output=True, timeout=30)
                assert result.returncode == 0, result.stdout + result.stderr
                return result.stdout
            namespace = 'Arion.ControlPlane.Service.ensure("arion")'
            killed = rpc(f'IO.puts(inspect({namespace}))')
            crash_requests = steady({'after'}, lambda seen: (rpc(f'Process.exit({namespace}, :kill)'), time.sleep(6)))
            assert rpc(f'IO.puts(inspect({namespace}))') != killed
            docs[0] = listener('http', http, 'after-crash')
            manifest.write_text('\n---\n'.join(json.dumps(d) for d in docs))
            command('apply', '-f', str(manifest))
            eventually(lambda: get_body() == 'after-crash')
            assert len(json.loads(command('status'))['arion']['clients']) == 1
            # Attach real remote IEx and mutate through the durable public API.
            master, slave = pty.openpty()
            shell = subprocess.Popen([str(ctl), 'shell'], env=env, stdin=slave,
                                     stdout=slave, stderr=slave)
            os.close(slave)
            try:
                docs[0] = listener('http', http, 'after-shell')
                manifest.write_text('\n---\n'.join(json.dumps(d) for d in docs))
                expression = ('{:ok, _} = Arion.Ctl.apply_file(' + json.dumps(str(manifest)) +
                              '); IO.puts(Enum.join(["ARION", "SHELL", "OK"], "_"))\n')
                os.write(master, expression.encode())
                output = b''
                deadline = time.monotonic() + 30
                while b'ARION_SHELL_OK' not in output and time.monotonic() < deadline:
                    if select.select([master], [], [], .2)[0]:
                        output += os.read(master, 65536)
                assert b'ARION_SHELL_OK' in output, output.decode(errors='replace')
                eventually(lambda: get_body() == 'after-shell')
                assert json.loads(command('get'))[0]['metadata']['name'] == 'http'
            finally:
                shell.terminate()
                shell.wait(timeout=10)
                os.close(master)
            server.terminate()
            server.wait(timeout=15)
            server = subprocess.Popen([str(ctl), 'serve'], env=env, stdout=ctl_log, stderr=subprocess.STDOUT)
            eventually(lambda: socket.create_connection(('127.0.0.1', ads), timeout=.2).close() is None)
            assert len(json.loads(command('get'))) == 2
            eventually(lambda: get_body() == 'after-shell')
            # Restart the proxy as well to verify replay from restored state.
            dataplane.terminate()
            dataplane.wait(timeout=15)
            dataplane = subprocess.Popen([str(proxy), '--config', str(config)], stdout=proxy_log, stderr=subprocess.STDOUT)
            eventually(lambda: get_body() == 'after-shell')
            # Rename the HTTP listener on the same port (the proxy uses SO_REUSEPORT): no request may fail
            # while both exist or after the old one is deleted, and then only the new body is served.
            renamed = root / 'renamed.yaml'
            renamed.write_text(json.dumps(listener('http-v2', http, 'renamed')))
            def rename(seen):
                command('apply', '-f', str(renamed))
                eventually(lambda: 'renamed' in seen)
                command('delete', 'Listener', 'http')
                deleted = len(seen)
                eventually(lambda: seen[deleted:][-10:] == ['renamed'] * 10)
            rename_requests = steady({'after-shell', 'renamed'}, rename)
            assert [d['metadata']['name'] for d in json.loads(command('get'))] == ['http-v2', 'mcp']
            command('delete', 'Listener', 'http-v2')
            def gone():
                try:
                    get_body()
                    return False
                except (OSError, urllib.error.URLError):
                    return True
            eventually(gone)
            assert len(json.loads(command('get'))) == 1
            print('PASS: CLI validation/apply/get/status/delete/shell, HTTP and MCP xDS, IEx durable apply, '
                  f'namespace crash recovery ({crash_requests} requests), same-port listener rename '
                  f'({rename_requests} requests), persistence and replay')
        except BaseException:
            ctl_log.flush(); proxy_log.flush()
            print((root / 'ctl.log').read_text()[-12000:])
            print((root / 'proxy.log').read_text()[-12000:])
            raise
        finally:
            for proc in [dataplane, server]:
                if proc and proc.poll() is None:
                    proc.terminate()
                    try: proc.wait(timeout=10)
                    except subprocess.TimeoutExpired: proc.kill(); proc.wait()
            ctl_log.close(); proxy_log.close()

if __name__ == '__main__':
    main()
