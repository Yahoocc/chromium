from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import functools, sys
class Handler(SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.0"
    def end_headers(self):
        self.send_header("Connection", "close")
        super().end_headers()
httpd = ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), functools.partial(Handler, directory=sys.argv[2]))
httpd.daemon_threads = True
httpd.serve_forever()
