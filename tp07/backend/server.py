#!/usr/bin/env python3
"""
Simple Backend API for Docker Compose to Kubernetes migration demo
"""
import http.server
import json
import os
import socket
from datetime import datetime

class HealthCheckHandler(http.server.BaseHTTPRequestHandler):
    """Simple HTTP handler with health check endpoint"""

    def log_message(self, format, *args):
        """Override to add timestamp to logs"""
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        print(f"[{timestamp}] {format % args}")

    def do_GET(self):
        """Handle GET requests"""
        if self.path == '/api/health' or self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()

            # Get environment info
            env_info = {
                "status": "healthy",
                "timestamp": datetime.now().isoformat(),
                "hostname": socket.gethostname(),
                "environment": {
                    "DATABASE_HOST": os.getenv('DATABASE_HOST', 'not set'),
                    "DATABASE_PORT": os.getenv('DATABASE_PORT', 'not set'),
                    "DATABASE_NAME": os.getenv('DATABASE_NAME', 'not set'),
                    "DATABASE_USER": os.getenv('DATABASE_USER', 'not set'),
                },
                "platform": os.getenv('PLATFORM', 'unknown')
            }

            self.wfile.write(json.dumps(env_info, indent=2).encode())

        elif self.path == '/api/info':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()

            info = {
                "service": "backend-api",
                "version": "1.0.0",
                "description": "Simple backend for K8s migration demo",
                "endpoints": [
                    "/api/health - Health check",
                    "/api/info - Service information"
                ]
            }

            self.wfile.write(json.dumps(info, indent=2).encode())

        else:
            self.send_response(404)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            error = {"error": "Not found", "path": self.path}
            self.wfile.write(json.dumps(error).encode())

def run_server(port=5000):
    """Run the HTTP server"""
    server_address = ('0.0.0.0', port)
    httpd = http.server.HTTPServer(server_address, HealthCheckHandler)

    print(f"""
╔═══════════════════════════════════════════════════════╗
║  Backend API Server                                   ║
║  Port: {port}                                          ║
║  Hostname: {socket.gethostname():<35} ║
║  Database: {os.getenv('DATABASE_HOST', 'not configured'):<35} ║
╚═══════════════════════════════════════════════════════╝
    """)

    print(f"Server started on http://0.0.0.0:{port}")
    print("Available endpoints:")
    print(f"  - http://0.0.0.0:{port}/api/health")
    print(f"  - http://0.0.0.0:{port}/api/info")
    print("\nPress Ctrl+C to stop the server\n")

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n\nServer stopped by user")
        httpd.server_close()

if __name__ == '__main__':
    port = int(os.getenv('PORT', 5000))
    run_server(port)
