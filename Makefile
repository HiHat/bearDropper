bearDropper: src/bearDropper.sh src/bddb.sh
	shellcheck src/bearDropper.sh
	sed -n '1,/_LOAD_MEAT_/p' src/bearDropper.sh | sed '/[[:space:]]*# shellcheck disable=/d;/_MEAT_/d' > bearDropper
	sed -n '/_BEGIN_MEAT_/,/_END_MEAT_/p' src/bddb.sh | sed '/[[:space:]]*# shellcheck disable=/d;/_MEAT_/d' >> bearDropper
	sed -n '/_LOAD_MEAT_/,$$p' src/bearDropper.sh | sed '/[[:space:]]*# shellcheck disable=/d;/_MEAT_/d;/^[[:space:]]*# _REM_/d' >> bearDropper
	chmod 755 bearDropper

install: bearDropper
	scp -O -p bearDropper $$TARGET:/usr/sbin/
	scp -O -p src/config/bearDropper $$TARGET:/etc/config/
	scp -O -p src/init.d/bearDropper $$TARGET:/etc/init.d/
	ssh $$TARGET "/etc/init.d/bearDropper stop; echo 'Processing historical log data'; /usr/sbin/bearDropper -m entire -f stdout; echo 'Starting background process'; /etc/init.d/bearDropper enable; /etc/init.d/bearDropper start"

clean:
	rm bearDropper
