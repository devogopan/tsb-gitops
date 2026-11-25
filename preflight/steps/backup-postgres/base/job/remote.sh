# Runs INSIDE the Postgres pod (busybox sh), started by `kubectl exec`.
# stdin line 1 = the database password. Arguments:
#   $1 backup dir  $2 database  $3 user  $4 file name  $5 backups to keep  $6 min free percent  $7 min bytes
# Prints "RESULT_*=" lines on success and "ERR ..." plus a non-zero exit on failure.
set -u
DIR="$1"; DB="$2"; USR="$3"; FILE="$4"; KEEP="$5"; MINFREE="$6"; MINBYTES="$7"
IFS= read -r PGPASSWORD || { echo "ERR no password received on stdin"; exit 10; }
export PGPASSWORD

# the backup directory must not be inside the live data directory
if [ -n "${PGDATA:-}" ]; then
  case "$DIR/" in "$PGDATA"/*) echo "ERR backup dir $DIR is inside PGDATA $PGDATA"; exit 11 ;; esac
else
  echo "WARN PGDATA is not set in the pod, cannot check the backup dir is outside it"
fi
mkdir -p "$DIR" 2>/dev/null || { echo "ERR cannot create $DIR (is it writable?)"; exit 12; }

DBSIZE="$(psql -U "$USR" -d "$DB" -tAc 'select pg_database_size(current_database())' 2>/dev/null)"
case "$DBSIZE" in ''|*[!0-9]*) echo "ERR cannot read the size of database $DB (wrong user, password or database?)"; exit 13 ;; esac

# free space on the volume that holds the backup (it is also the database volume)
set -- $(df -Pk "$DIR" | tail -1)
TOTAL_KB="$2"; AVAIL_KB="$4"
NEED_KB=$(( DBSIZE / 1024 + 1 ))
[ "$AVAIL_KB" -ge "$NEED_KB" ] || { echo "ERR not enough free space: ${AVAIL_KB} KB free, database is ${NEED_KB} KB"; exit 18; }
AFTER_PCT=$(( (AVAIL_KB - NEED_KB) * 100 / TOTAL_KB ))
[ "$AFTER_PCT" -ge "$MINFREE" ] || { echo "ERR the dump could leave the volume only ${AFTER_PCT}% free (minimum ${MINFREE}%), the database shares this volume"; exit 19; }

TMP="$DIR/$FILE.part"
RCF="$DIR/.pgdump.rc"
{ pg_dump -U "$USR" "$DB"; echo $? > "$RCF"; } | gzip > "$TMP"
RC="$(cat "$RCF" 2>/dev/null || echo 99)"; rm -f "$RCF"
[ "$RC" = "0" ] || { rm -f "$TMP"; echo "ERR pg_dump failed with exit code $RC"; exit 14; }
gzip -t "$TMP" 2>/dev/null || { rm -f "$TMP"; echo "ERR the dump is not a valid gzip file"; exit 15; }
zcat "$TMP" | tail -n 5 | grep -q 'PostgreSQL database dump complete' || { rm -f "$TMP"; echo "ERR the dump has no 'PostgreSQL database dump complete' trailer, it is incomplete"; exit 16; }
SIZE="$(wc -c < "$TMP" | tr -d ' ')"
[ "$SIZE" -ge "$MINBYTES" ] || { rm -f "$TMP"; echo "ERR the dump is only $SIZE bytes (minimum $MINBYTES)"; exit 17; }
mv "$TMP" "$DIR/$FILE"
( cd "$DIR" && sha256sum "$FILE" > "$FILE.sha256" ) || { echo "ERR cannot compute sha256"; exit 20; }
SHA="$(cut -d' ' -f1 "$DIR/$FILE.sha256")"

# keep the newest $KEEP dumps of this database, remove older ones (and their .sha256)
ls -1t "$DIR"/"$DB"-*.sql.gz 2>/dev/null | tail -n +$(( KEEP + 1 )) | while IFS= read -r old; do
  rm -f "$old" "$old.sha256"; echo "PRUNED $old"
done

echo "RESULT_FILE=$DIR/$FILE"
echo "RESULT_SIZE=$SIZE"
echo "RESULT_SHA=$SHA"
echo "RESULT_DBSIZE=$DBSIZE"
echo "RESULT_FREEPCT=$AFTER_PCT"
