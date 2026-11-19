import CollectionTesting
import Foundation
import SyncTesting

/// A TLS terminator for Anki's real local sync server. The test's CA is never
/// installed on the Mac, and its private keys stay in a disposable folder.
@MainActor
final class LocalSyncTLS {
    let certificate: String
    let address: String
    private let folder: TemporaryFolder
    private let server: Process

    init(for upstream: SyncServer) async throws {
        let folder = try TemporaryFolder()
        let workingDirectory = folder.url
        let extensions = """
        [ca]
        basicConstraints = critical,CA:TRUE
        keyUsage = critical,keyCertSign,cRLSign
        [leaf]
        basicConstraints = critical,CA:FALSE
        keyUsage = digitalSignature,keyEncipherment
        extendedKeyUsage = serverAuth
        subjectAltName = IP:127.0.0.1,DNS:localhost
        """
        try extensions.write(to: workingDirectory.appendingPathComponent("extensions.cnf"), atomically: true, encoding: .utf8)

        try Self.openssl(in: workingDirectory, [
            "req", "-new", "-nodes", "-newkey", "rsa:2048", "-subj", "/CN=Hayaki Local Test CA",
            "-keyout", "ca.key", "-out", "ca.csr",
        ])
        try Self.openssl(in: workingDirectory, [
            "x509", "-req", "-in", "ca.csr", "-signkey", "ca.key", "-out", "ca.pem",
            "-days", "1", "-extfile", "extensions.cnf", "-extensions", "ca",
        ])
        try Self.openssl(in: workingDirectory, [
            "req", "-new", "-nodes", "-newkey", "rsa:2048", "-subj", "/CN=localhost",
            "-keyout", "server.key", "-out", "server.csr",
        ])
        try Self.openssl(in: workingDirectory, [
            "x509", "-req", "-in", "server.csr", "-CA", "ca.pem", "-CAkey", "ca.key", "-CAcreateserial",
            "-out", "server.pem", "-days", "1", "-extfile", "extensions.cnf", "-extensions", "leaf",
        ])
        certificate = try String(contentsOf: workingDirectory.appendingPathComponent("ca.pem"), encoding: .utf8)

        let log = workingDirectory.appendingPathComponent("proxy.log")
        try Data().write(to: log)
        let output = try FileHandle(forWritingTo: log)
        defer { try? output.close() }

        let server = Process()
        server.executableURL = URL(filePath: "/usr/bin/env")
        server.currentDirectoryURL = workingDirectory
        let syncPort = URL(string: upstream.address)?.port ?? 80
        server.arguments = ["python3", "-u", "-c", Self.proxyScript, String(syncPort)]
        server.standardError = output
        try server.run()
        let portFile = workingDirectory.appendingPathComponent("port")
        var port: Int?
        do {
            try await eventually(timeout: .seconds(20), "the local TLS endpoint to start") {
                port = (try? String(contentsOf: portFile, encoding: .utf8)).flatMap(Int.init)
                return port != nil || !server.isRunning
            }
        } catch {
            if server.isRunning { server.terminate() }
            if error is CancellationError { throw error }
            throw Self.startupError(reason: String(describing: error), log: log)
        }
        guard let port, server.isRunning else {
            throw Self.startupError(reason: "The local TLS proxy exited before listening", log: log)
        }

        self.folder = folder
        self.server = server
        address = "https://127.0.0.1:\(port)/"
    }

    deinit {
        if server.isRunning { server.terminate() }
    }

    private static func startupError(reason: String, log: URL) -> ProxyStartupError {
        let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        return ProxyStartupError(description: output.isEmpty ? reason : "\(reason)\n\(output)")
    }

    private struct ProxyStartupError: Error, CustomStringConvertible {
        let description: String
    }

    private static func openssl(in folder: URL, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/openssl")
        process.currentDirectoryURL = folder
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    private static let proxyScript = """
    import http.client
    import http.server
    import os
    import ssl
    import sys

    class Proxy(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            if self.headers.get("Transfer-Encoding") == "chunked":
                chunks = []
                while True:
                    size = int(self.rfile.readline().strip(), 16)
                    if not size:
                        self.rfile.readline()
                        break
                    chunks.append(self.rfile.read(size))
                    self.rfile.readline()
                body = b"".join(chunks)
            else:
                body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            excluded = {"host", "connection", "transfer-encoding", "content-length"}
            headers = {key: value for key, value in self.headers.items() if key.lower() not in excluded}
            with_backend = http.client.HTTPConnection("127.0.0.1", int(sys.argv[1]))
            try:
                with_backend.request("POST", self.path, body, headers)
                response = with_backend.getresponse()
                result = response.read()
                self.send_response(response.status)
                for key, value in response.headers.items():
                    if key.lower() not in excluded:
                        self.send_header(key, value)
                self.send_header("Content-Length", str(len(result)))
                self.end_headers()
                self.wfile.write(result)
            finally:
                with_backend.close()

        def log_message(self, *args):
            pass

    proxy = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Proxy)
    tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    tls.load_cert_chain("server.pem", "server.key")
    proxy.socket = tls.wrap_socket(proxy.socket, server_side=True)
    with open("port.tmp", "w") as port_file:
        port_file.write(str(proxy.server_port))
    os.replace("port.tmp", "port")
    proxy.serve_forever()
    """
}
