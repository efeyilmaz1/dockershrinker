import subprocess
import json
import sys

def get_image_size(image_name):
    """Gets the virtual size of a docker image in MB."""
    try:
        result = subprocess.run(
            ["docker", "image", "inspect", image_name],
            capture_output=True,
            text=True,
            check=True
        )
        data = json.loads(result.stdout)
        size_bytes = data[0].get("Size", 0)
        return size_bytes / (1024 * 1024)
    except Exception as e:
        print(f"Error inspecting {image_name}: {e}")
        return None

def main():
    if len(sys.argv) != 3:
        print("Usage: python size_calculator.py <original_image> <shrunk_image>")
        sys.exit(1)

    orig_img = sys.argv[1]
    shrunk_img = sys.argv[2]

    orig_size = get_image_size(orig_img)
    shrunk_size = get_image_size(shrunk_img)

    if orig_size is None or shrunk_size is None:
        print("Could not retrieve sizes. Ensure both images exist locally.")
        sys.exit(1)

    reduction_pct = ((orig_size - shrunk_size) / orig_size) * 100

    print("="*60)
    print("📦 CI/CD İmaj Optimizasyon Raporu")
    print("="*60)
    print(f"[CI] Orijinal İmaj Boyutu : {orig_size:.2f} MB")
    print(f"[CI] Küçültülmüş Boyut    : {shrunk_size:.2f} MB")
    print(f"     Tasarruf Oranı       : %{reduction_pct:.2f} 🚀")
    print("="*60)

if __name__ == "__main__":
    main()
