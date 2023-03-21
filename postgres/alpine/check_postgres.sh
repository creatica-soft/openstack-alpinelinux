#!/bin/ash

pg_isready -h 0.0.0.0 -d postgres -U postgres
while [[ $? > 0 ]]; do
  echo "Postgres is not ready. Attempt to start it"
  pg_ctl start -D /var/lib/postgresql/13/data
  sleep 5
  pg_isready -h 0.0.0.0 -d postgres -U postgres
done

MODE=`psql -h 0.0.0.0 -U postgres -d postgres --csv -t -n -c 'select pg_is_in_recovery();'`
if [[ "${MODE}" == "t" ]]; then
  exit 1
elif [[ "${MODE}" == "f" ]]; then
  exit 0
else
  exit 2
fi
