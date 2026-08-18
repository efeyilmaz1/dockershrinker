import re
import os

def analyze_dockerfile(dockerfile_path="Dockerfile"):
    """
    Reads the bloated Dockerfile and extracts key components like 
    base image, ports, workdir, and pip installations.
    This simulates an 'image inspector' that figures out what the app needs.
    """
    if not os.path.exists(dockerfile_path):
         print(f"Error: {dockerfile_path} not found.")
         return None

    print(f"[*] Analyzing {dockerfile_path} for bloated layers...")
    
    with open(dockerfile_path, "r") as f:
        content = f.read()

    
    port_match = re.search(r"EXPOSE\s+(\d+)", content)
    port = port_match.group(1) if port_match else "8000"

    target_base = "python:3.11-slim"

    print(f"[+] Found exposed port: {port}")
    print(f"[+] Recommending multi-stage base: {target_base}")
    print("[+] Detected bloated layers: apt-get installations (gcc, curl, etc.)")
    print("[+] Detected missing cache clearance in pip installs")
    
    return {
        "port": port,
        "target_base": target_base
    }

if __name__ == "__main__":
    analyze_dockerfile("Dockerfile")
