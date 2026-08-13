from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import functools
import sys

class Handler(SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.0"
    def end_headers(self):
        self.send_header("Connection", "close")
        super().end_headers()

port = int(sys.argv[1])
directory = sys.argv[2]
handler = functools.partial(Handler, directory=directory)
httpd = ThreadingHTTPServer(("127.0.0.1", port), handler)
httpd.daemon_threads = True
httpd.serve_forever()
