#!/bin/sh
BSDlive goo
BASE="$BSD_DEV/website"
WWW="$BASE/www"
INDEX=$WWW/index.html
LIVE="/.worker/gate/var/squid/reports"
TARGETPAGES="$BSD_DEV/paepckehh.github.io $BSD_DEV/pages"
if [ ! -x "$BASE" ]; then exit 1; fi
UUID="$(uuidgen)"
mv -f $WWW $WWW.$UUID > /dev/null 2>&1
rm -rf $WWW.$UUID > /dev/null 2>&1
mkdir -p $WWW || exit 1
cp -f $BASE/.template.index.html $INDEX || exit 1
ls -I $BSD_DEV | while read line; do
	cd $BSD_DEV/$line > /dev/null 2>&1 || continue
	echo "###################################################################################"
	echo "### [start] [$line]"
	if [ -e .export ]; then
		NEW="$WWW/$line"
		mkdir -p "$NEW" || exit 1
		cd $NEW || exit 1
		cp $BASE/.template.project.html index.html || exit 1
		if [ -e $BSD_DEV/$line/.apionly ]; then
			sed -i '' -e "/INSTALL/d" index.html
			sed -i '' -e "/DOWNLOAD/d" index.html
		fi
		if [ -e $BSD_DEV/$line/.dataonly ]; then
			sed -i '' -e "/DOCS/d" index.html
			sed -i '' -e "/INSTALL/d" index.html
			sed -i '' -e "/DOWNLOAD/d" index.html
		fi
		if [ -e $BSD_DEV/$line/.norelease ]; then
			sed -i '' -e "/DOWNLOAD/d" index.html
		fi
		if [ ! -e $BSD_DEV/$line/.github.com ]; then
			sed -i '' -e "/github/d" index.html
		fi
		if [ ! -e $BSD_DEV/$line/.gitlab.com ]; then
			sed -i '' -e "/gitlab/d" index.html
		fi
		if [ ! -e $BSD_DEV/$line/.codeberg.org ]; then
			sed -i '' -e "/codeberg/d" index.html
		fi
		if [ ! -e $BSD_DEV/$line/.sr.ht ]; then
			sed -i '' -e "/git.sr.ht/d" index.html
		fi
		sed -i '' -e "s/XXXPKGXXX/$line/g" index.html
		echo "<tr><td><a href="$line"><button>$line</button></a></td></tr>" >> $INDEX
		# sh /etc/goo/goo.mdtohtml $BSD_DEV/$line/README.md readme.html
		cd $BSD_DEV/$line > /dev/null 2>&1 || continue
		if [ -x .git ]; then
			if [ "$DIST" == "pnoc" ]; then
				if [ -e go.mod ]; then
					export HTTPS_PROXY=127.0.0.80:8080
					export SSL_CERT_FILE=/etc/ssl/rootCA.pem
					export GOPROXY="proxy.golang.org"
					export GOSUMDB="sum.golang.org+033de0ae+Ac4zctda0e5eza+HJyk9SxEdh+s3Ux18htTTAD8OuAn8"
					rm -rf go.mod go.sum > /dev/null 2>&1
					/usr/local/goo/.freebsd.arm/bin/go mod init paepcke.de/$line
					case $line in
					gps*) ;;
					*) sed -i '' -e 's/go 1\.20/go 1\.19/g' go.mod ;;
					esac
					/usr/local/goo/.freebsd.arm/bin/go mod tidy
				fi
				if [ -e go.mod ]; then
					sh /etc/action/fmt.golang
				fi
				/usr/bin/git rm -r --cached .
				/usr/bin/git add .
				/usr/bin/git commit -m "auto: sync upstream / update dependencies"
				/usr/bin/git gc
				sh /etc/action/git.push
			fi
			if [ "$DIST" == "bsrv" ]; then
				/usr/bin/git prune --expire=now
				/usr/bin/git reflog expire --expire-unreachable=now --rewrite --all
				/usr/bin/git pack-refs --all
				/usr/bin/git repack -n -a -d -f --depth=64 --window=300 --threads=0
				/usr/bin/git prune-packed
				/usr/bin/git fsck --strict --unreachable --dangling --full --cache
			fi
			LATEST=$(doasgit -C $BSD_GIT/.repo/github_com_paepckehh_$line tag | tail -n 1)
			echo "$line => tag: $LATEST"
			if [ ! -z "$UPSIG" ]; then
				HQ_ADD_SIGNIFY=true sh /etc/action/git.sign github_com_paepckehh_$line $LATEST
			fi
		fi
		echo "### [done] [$line]"
		echo "###################################################################################"
	fi
done
echo "</table></div><br><br><br><br><a href="imp.html"><button>[impressum][contact]</button></a><br></body></html>" >> $INDEX
cp -f $BASE/.template.imp.html $WWW/imp.html
cp -f $BASE/.template.keys $WWW/keys/keys
cp -f $BASE/.template.keys $WWW/paepcke.keys
chown -R 0:0 $WWW
chmod -R o=rX,g=rX,u=rX $WWW
for PAGES in $TARGETPAGES; do
	if [ -x "$PAGES" ]; then
		cp -af $WWW/* $PAGES/
		(
			cd $PAGES && (
				/usr/bin/git add .
				/usr/bin/git commit -m "generate static site"
				/usr/bin/git gc
				if [ "$DIST" == "pnoc" ]; then sh /etc/action/git.push; fi
			)
		)
	fi
done
if [ -x "$LIVE" ]; then
	mv -f $LIVE/www $LIVE/www.$UUID
	cp -af $WWW $LIVE/
	rm -rf $LIVE/www.$UUID > /dev/null 2>&1
fi
if [ "$DIST" == "bsrv" ]; then cd $GOMODCACHE && fsdd --hard-link .; fi
