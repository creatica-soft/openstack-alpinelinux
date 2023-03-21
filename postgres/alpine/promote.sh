#!/bin/ash

pg_isready -h 0.0.0.0 -d postgres -U postgres
while [[ $? > 0 ]]; do
  pg_ctl start -D /var/lib/postgresql/13/data
  sleep 5
  pg_isready -h 0.0.0.0 -d postgres -U postgres
done

MODE=`psql -h 0.0.0.0 -U postgres -d postgres --csv -t -n -c 'select pg_is_in_recovery();'`
if [[ "${MODE}" == "f" ]]; then
  exit 1
elif [[ "${MODE}" == "t" ]]; then
#  rm -f /var/lib/postgresql/13/data/postgresql.conf
#  ln -s /etc/postgresql/postgresql.master /var/lib/postgresql/13/data/postgresql.conf
  pg_ctl promote -D /var/lib/postgresql/13/data
else
  exit 2
fi
