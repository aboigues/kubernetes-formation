#!/usr/bin/env python3
"""
Script pour valider la syntaxe YAML de tous les fichiers du TP5
"""
import yaml
import sys
import os
from pathlib import Path

def validate_yaml_file(file_path):
    """Valide un fichier YAML et retourne True si valide, False sinon"""
    try:
        with open(file_path, 'r') as f:
            # yaml.safe_load_all pour supporter les fichiers avec plusieurs documents
            documents = list(yaml.safe_load_all(f))
            if not documents:
                print(f"  ⚠️  {file_path.name}: Fichier vide")
                return False
            print(f"  ✅ {file_path.name}: Valide ({len(documents)} document(s))")
            return True
    except yaml.YAMLError as e:
        print(f"  ❌ {file_path.name}: Erreur YAML - {e}")
        return False
    except Exception as e:
        print(f"  ❌ {file_path.name}: Erreur - {e}")
        return False

def main():
    """Valide tous les fichiers YAML dans le répertoire courant"""
    tp5_dir = Path(__file__).parent
    yaml_files = sorted(tp5_dir.glob("*.yaml"))

    if not yaml_files:
        print("Aucun fichier YAML trouvé")
        return 1

    print(f"Validation de {len(yaml_files)} fichiers YAML...\n")

    valid_count = 0
    invalid_count = 0

    for yaml_file in yaml_files:
        if validate_yaml_file(yaml_file):
            valid_count += 1
        else:
            invalid_count += 1

    print(f"\n{'='*60}")
    print(f"Résumé:")
    print(f"  Fichiers valides: {valid_count}")
    print(f"  Fichiers invalides: {invalid_count}")
    print(f"  Total: {len(yaml_files)}")
    print(f"{'='*60}")

    return 0 if invalid_count == 0 else 1

if __name__ == "__main__":
    sys.exit(main())
