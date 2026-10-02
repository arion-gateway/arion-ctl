#!/usr/bin/env python3
"""Print an arionctl Secret manifest containing a PEM certificate and private key."""
import argparse
import json
from pathlib import Path

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("certificate", type=Path)
    parser.add_argument("private_key", type=Path)
    args = parser.parse_args()
    manifest = {
        "apiVersion": "ctl.arion.io/v1alpha1",
        "kind": "Secret",
        "metadata": {"name": "docs-cert", "fleet": "arion"},
        "spec": {"tlsCertificate": {
            "certificateChain": {"inlineString": args.certificate.read_text()},
            "privateKey": {"inlineString": args.private_key.read_text()},
        }},
    }
    print(json.dumps(manifest, indent=2))

if __name__ == "__main__":
    main()
