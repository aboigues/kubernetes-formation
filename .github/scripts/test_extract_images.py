"""Tests du calcul des catégories SARIF de .github/scripts/extract-images.py.

Lancement : python3 -m unittest discover -s .github/scripts -p 'test_*.py'
"""
import importlib.util
import unittest
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    "extract_images", Path(__file__).with_name("extract-images.py")
)
module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(module)
categories_sarif = module.categories_sarif


class CategoriesSarif(unittest.TestCase):
    def test_image_seule_categorie_sans_tag(self):
        self.assertEqual(
            categories_sarif(["traefik:v3.7.17"]),
            {"traefik:v3.7.17": "trivy-image-traefik"},
        )

    def test_montee_de_version_garde_la_categorie(self):
        # Le cœur du correctif : un bump ne doit plus laisser d'alertes fantômes.
        avant = categories_sarif(["grafana/alloy:v1.20.1"])
        apres = categories_sarif(["grafana/alloy:v1.21.3"])
        self.assertEqual(list(avant.values()), list(apres.values()))

    def test_plusieurs_tags_d_une_image_ne_s_ecrasent_pas(self):
        cats = categories_sarif(["grafana/loki:3.7.2", "grafana/loki:3.7.8"])
        self.assertEqual(
            cats,
            {
                "grafana/loki:3.7.2": "trivy-image-grafana-loki-rang-1",
                "grafana/loki:3.7.8": "trivy-image-grafana-loki-rang-2",
            },
        )

    def test_montee_d_un_des_tags_garde_les_rangs(self):
        avant = categories_sarif(["grafana/loki:3.7.2", "grafana/loki:3.7.8"])
        apres = categories_sarif(["grafana/loki:3.7.8", "grafana/loki:3.7.9"])
        self.assertEqual(sorted(avant.values()), sorted(apres.values()))

    def test_tri_par_version_et_non_alphabetique(self):
        cats = categories_sarif(["registry:3.1.2", "registry:2", "registry:3", "nginx:1.9", "nginx:1.10"])
        self.assertEqual(cats["registry:2"], "trivy-image-registry-rang-1")
        self.assertEqual(cats["registry:3"], "trivy-image-registry-rang-2")
        self.assertEqual(cats["registry:3.1.2"], "trivy-image-registry-rang-3")
        self.assertEqual(cats["nginx:1.9"], "trivy-image-nginx-rang-1")
        self.assertEqual(cats["nginx:1.10"], "trivy-image-nginx-rang-2")

    def test_variante_de_tag(self):
        cats = categories_sarif(["postgres:18-alpine", "postgres:18"])
        self.assertEqual(cats["postgres:18"], "trivy-image-postgres-rang-1")
        self.assertEqual(cats["postgres:18-alpine"], "trivy-image-postgres-rang-2")

    def test_registre_avec_port_digest_et_sans_tag(self):
        cats = categories_sarif(
            ["localhost:5000/app:1.0", "gcr.io/distroless/static-debian12:nonroot", "busybox", "alpine@sha256:abc"]
        )
        self.assertEqual(cats["localhost:5000/app:1.0"], "trivy-image-localhost-5000-app")
        self.assertEqual(
            cats["gcr.io/distroless/static-debian12:nonroot"], "trivy-image-gcr.io-distroless-static-debian12"
        )
        self.assertEqual(cats["busybox"], "trivy-image-busybox")
        self.assertEqual(cats["alpine@sha256:abc"], "trivy-image-alpine")

    def test_categories_toutes_distinctes(self):
        images = ["registry:2", "registry:3", "registry:3.1.2", "postgres:18", "postgres:18-alpine", "redis:8-alpine"]
        cats = categories_sarif(images)
        self.assertEqual(len(set(cats.values())), len(images))


if __name__ == "__main__":
    unittest.main()
