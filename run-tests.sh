#!/usr/bin/env bash
#
# run-tests.sh — Exécute les tests unitaires en s'adaptant automatiquement au
# type de projet (Angular / npm ou Spring Boot / Gradle) et produit un rapport
# au format JUnit XML dans le répertoire test-results/.
#
# Codes de sortie :
#   0 : tests réussis
#   1 : au moins un test a échoué (code propagé depuis le lanceur de tests)
#   2 : type de projet non reconnu
#   3 : dépendance requise manquante
#
set -euo pipefail

RESULTS_DIR="test-results"

log() { printf '\033[1;34m[run-tests]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[run-tests] ERREUR :\033[0m %s\n' "$*" >&2; }

# --- Détection automatique du type de projet ---------------------------------
detect_project_type() {
  if [ -f "build.gradle" ] || [ -f "gradlew" ]; then
    echo "java"
  elif [ -f "package.json" ]; then
    echo "node"
  else
    echo "unknown"
  fi
}

# --- Nettoyage des artefacts de tests précédents -----------------------------
clean_artifacts() {
  log "Nettoyage des artefacts de tests précédents"
  rm -rf "$RESULTS_DIR" build/test-results reports coverage
  mkdir -p "$RESULTS_DIR"
}

# --- Vérification de la présence d'une commande ------------------------------
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Dépendance manquante : $1"; exit 3; }
}

# --- Tests Spring Boot / Gradle ----------------------------------------------
run_java_tests() {
  log "Projet détecté : Spring Boot / Gradle"
  require_cmd java
  if [ ! -x "./gradlew" ]; then
    [ -f "./gradlew" ] && chmod +x ./gradlew || { err "gradlew introuvable"; exit 3; }
  fi

  ./gradlew clean test
  local rc=$?

  # Collecte des rapports JUnit générés par Gradle
  if compgen -G "build/test-results/test/*.xml" >/dev/null; then
    cp build/test-results/test/*.xml "$RESULTS_DIR"/
  fi
  return $rc
}

# --- Tests Angular / npm ------------------------------------------------------
run_node_tests() {
  log "Projet détecté : Angular / npm"
  require_cmd node
  require_cmd npm
  if [ ! -d "node_modules" ]; then
    log "node_modules absent — installation des dépendances via npm ci"
    npm ci --cache .npm --prefer-offline
  fi

  npm test
  local rc=$?

  # Karma (karma-junit-reporter) écrit directement dans test-results/.
  # Filet de sécurité si une configuration antérieure écrit ailleurs.
  if ! compgen -G "$RESULTS_DIR/*.xml" >/dev/null 2>&1; then
    find reports -name '*.xml' -exec cp {} "$RESULTS_DIR"/ \; 2>/dev/null || true
  fi
  return $rc
}

main() {
  local type
  type="$(detect_project_type)"
  if [ "$type" = "unknown" ]; then
    err "Type de projet non reconnu (ni build.gradle ni package.json trouvé)."
    exit 2
  fi

  clean_artifacts

  # On désactive l'arrêt sur erreur autour de l'exécution des tests pour
  # pouvoir collecter les rapports même en cas d'échec, puis propager le code.
  local rc=0
  set +e
  case "$type" in
    java) run_java_tests ;;
    node) run_node_tests ;;
  esac
  rc=$?
  set -e

  if [ "$rc" -eq 0 ]; then
    log "Tests réussis. Rapports JUnit disponibles dans $RESULTS_DIR/"
  else
    err "Échec des tests (code $rc). Rapports disponibles dans $RESULTS_DIR/"
  fi
  exit "$rc"
}

main "$@"
