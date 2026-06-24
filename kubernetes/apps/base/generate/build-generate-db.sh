#!/usr/bin/env bash
set -uo pipefail

DB_HOST="${DB_HOST:-generate-mssql}"
DB_PORT="${DB_PORT:-1433}"
DB_USER="${DB_USER:-sa}"
DB_PASSWORD="${DB_PASSWORD:?set DB_PASSWORD}"
DB_NAME="${DB_NAME:-Generate}"

CEDS_IDS_TAG="${CEDS_IDS_TAG:-v13.0.0.0}"
CEDS_DW_TAG="${CEDS_DW_TAG:-v13.0.0.0}"
GENERATE_TAG="${GENERATE_TAG:-V13.2}"

WORK="$(mktemp -d)"
SQLCMD="/opt/mssql-tools18/bin/sqlcmd"
RUN="$SQLCMD -S ${DB_HOST},${DB_PORT} -U ${DB_USER} -P ${DB_PASSWORD} -C -b -d ${DB_NAME}"
RUN_MASTER="$SQLCMD -S ${DB_HOST},${DB_PORT} -U ${DB_USER} -P ${DB_PASSWORD} -C -b -d master"

fetch() {
  local org="$1" repo="$2" tag="$3" dest="$4"
  echo "Downloading ${org}/${repo}@${tag}"
  curl -fsSL "https://github.com/${org}/${repo}/archive/refs/tags/${tag}.tar.gz" -o "${WORK}/${repo}.tar.gz" \
    || curl -fsSL "https://github.com/${org}/${repo}/archive/refs/heads/master.tar.gz" -o "${WORK}/${repo}.tar.gz"
  mkdir -p "${dest}"
  tar -xzf "${WORK}/${repo}.tar.gz" -C "${dest}" --strip-components=1
}

prep() {
  sed -E \
    -e '/^[[:space:]]*CREATE[[:space:]]+DATABASE/Id' \
    -e '/^[[:space:]]*ALTER[[:space:]]+DATABASE/Id' \
    -e '/^[[:space:]]*USE[[:space:]]+\[/Id' \
    -e "s/CEDS-IDS-V[0-9-]+/${DB_NAME}/g" \
    -e "s/CEDS-Data-Warehouse-V[0-9-]+/${DB_NAME}/g" \
    "$1"
}

run_file() {
  local f="$1"
  prep "$f" > "${WORK}/current.sql"
  $RUN -i "${WORK}/current.sql"
}

run_dir_fixedpoint() {
  local dir="$1" label="$2"
  mapfile -t pending < <(find "$dir" -maxdepth 1 -name '*.sql' | sort)
  local total="${#pending[@]}"
  echo ">>> ${label}: ${total} scripts"
  local pass=0
  while :; do
    pass=$((pass + 1))
    local failed=()
    for f in "${pending[@]}"; do
      if ! run_file "$f" >/dev/null 2>"${WORK}/err.txt"; then
        failed+=("$f")
      fi
    done
    echo "    pass ${pass}: ${#failed[@]} of ${#pending[@]} failed"
    if [ "${#failed[@]}" -eq 0 ] || [ "${#failed[@]}" -eq "${#pending[@]}" ]; then
      pending=("${failed[@]}")
      break
    fi
    pending=("${failed[@]}")
  done
  if [ "${#pending[@]}" -gt 0 ]; then
    echo "    unresolved in ${label}:"
    printf '      %s\n' "${pending[@]##*/}"
    tail -n 5 "${WORK}/err.txt" | sed 's/^/      last error: /'
  fi
}

ensure_db() {
  echo ">>> Ensuring database ${DB_NAME} exists"
  $RUN_MASTER -Q "IF DB_ID('${DB_NAME}') IS NULL CREATE DATABASE [${DB_NAME}];"
}

run_first_match() {
  local base="$1" pattern="$2"
  local f
  f="$(find "$base" -type f -iname "$pattern" | sort | head -n1)"
  if [ -z "$f" ]; then
    echo "    (skip) no match for ${pattern} under ${base}"
    return 0
  fi
  echo "    running ${f#$WORK/}"
  run_file "$f"
}

main() {
  fetch CEDStandards CEDS-IDS "${CEDS_IDS_TAG}" "${WORK}/ids"
  fetch CEDStandards CEDS-Data-Warehouse "${CEDS_DW_TAG}" "${WORK}/dw"
  fetch CEDS-Collaborative-Exchange Generate "${GENERATE_TAG}" "${WORK}/gen"

  ensure_db

  echo ">>> CEDS IDS foundation"
  run_first_match "${WORK}/ids/src/ddl" "CEDS-IDS*.sql"
  run_first_match "${WORK}/ids/src/metadata" "Populate-CEDS-Element-Tables*.sql"
  run_first_match "${WORK}/ids/src/reference-data" "Populate-CEDS-Ref-Tables*.sql"

  echo ">>> CEDS Data Warehouse"
  run_first_match "${WORK}/dw/src/ddl" "CEDS-Data-Warehouse-V*.sql"
  run_first_match "${WORK}/dw/src/dimension-data" "*Junk-Table-Dimension-Population*.sql"

  local gdb="${WORK}/gen/generate.database"
  echo ">>> Generate schemas and objects"
  run_dir_fixedpoint "${gdb}/Schemas" "Schemas"
  run_dir_fixedpoint "${gdb}/TableTypes/Create" "TableTypes"
  run_dir_fixedpoint "${gdb}/Tables/Create" "Tables"
  run_dir_fixedpoint "${gdb}/Functions/Create" "Functions"
  run_dir_fixedpoint "${gdb}/Views/Create" "Views"
  run_dir_fixedpoint "${gdb}/StoredProcedures/Create" "StoredProcedures"
  run_dir_fixedpoint "${gdb}/Indexes" "Indexes"

  echo ">>> Generate metadata (reports, categories, file specs)"
  for f in \
    "App.TableTypes.Metadata.sql" \
    "App.Categories.Metadata.sql" \
    "App.CategorySets.Metadata.sql" \
    "App.AddCategorySets.Metadata.sql" \
    "App.CategorySets_FS_No_CategorySet.Metadata.sql" \
    "App.CedsConnections.Metadata.sql" \
    "App.FileColumns.Metadata.sql" \
    "App.FileHeader.Metadata.sql" \
    "App.FileSubmissions.Metadata.sql" \
    "App.GenerateReports.Metadata.sql" \
    "App.ViewDefinitions.Metadata.sql"; do
    if [ -f "${gdb}/Metadata/${f}" ]; then
      echo "    metadata ${f}"
      run_file "${gdb}/Metadata/${f}" || echo "    (warn) ${f} reported errors"
    fi
  done

  echo ">>> Stamping database version"
  $RUN -Q "IF EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id=s.schema_id WHERE s.name='App' AND t.name='GenerateConfigurations') BEGIN IF EXISTS (SELECT 1 FROM App.GenerateConfigurations WHERE GenerateConfigurationCategory='Database' AND GenerateConfigurationKey='DatabaseVersion') UPDATE App.GenerateConfigurations SET GenerateConfigurationValue='13.2' WHERE GenerateConfigurationCategory='Database' AND GenerateConfigurationKey='DatabaseVersion'; ELSE INSERT INTO App.GenerateConfigurations (GenerateConfigurationCategory, GenerateConfigurationKey, GenerateConfigurationValue) VALUES ('Database','DatabaseVersion','13.2'); END"

  echo ">>> Object counts by schema"
  $RUN -Q "SELECT s.name AS [schema], COUNT(*) AS tables FROM sys.tables t JOIN sys.schemas s ON t.schema_id=s.schema_id GROUP BY s.name ORDER BY s.name;"

  rm -rf "${WORK}"
  echo ">>> Build complete"
}

main "$@"
