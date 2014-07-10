
git remote update
git reset --hard origin/master

COMMITS=`git log --reverse | grep commit | sed -e 's/commit //'`
RESULTSFILE="results.txt"

rm -f ${RESULTSFILE}

for c in $COMMITS; do

    git reset --hard $c
    echo $c >> "${RESULTSFILE}"
    git show $c | head -n 5 | tail -n 1 >> "${RESULTSFILE}"
    lua server.lua &
    sleep 5
    ab -n 10000 -c 10 -k http://127.0.0.1:8080/ | grep "Requests per second" >> "${RESULTSFILE}"
    killall lua
    echo >> "${RESULTSFILE}"

done

