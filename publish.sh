#!/bin/sh
setup() {
	hq u
	BSDlive goo
	go version || exit 1
	GOPREPONLY="true" /etc/action/fmt.golang || exit 1
	if [ "$DIST" == "pnoc" ]; then
		export HTTPS_PROXY=127.0.0.80:8080
		export SSL_CERT_FILE=/etc/ssl/rootCA.pem
		export GOPROXY="proxy.golang.org"
		export GOSUMDB="sum.golang.org+033de0ae+Ac4zctda0e5eza+HJyk9SxEdh+s3Ux18htTTAD8OuAn8"
	else
		export GOPROXY="failfast"
	fi
	export BASE="$BSD_DEV/website"
	export WWW="$BASE/www"
	export INDEX=$WWW/index.html
	export LIVE="/.worker/gate/var/squid/reports"
	export TARGETPAGES="$BSD_DEV/paepckehh.github.io $BSD_DEV/pages"
	export UUID="$(uuidgen)"
	export REPOS="$(cd $BSD_DEV && ls -I | grep -v action)"
	if [ -z "$REPOS" ] || [ ! -x "$BASE" ]; then echo "unable to access repo" && exit 1; fi
	rm -rf $WWW || exit 1
	mkdir -p $WWW || exit 1
	cp -f $BASE/.template.index.html $INDEX || exit 1
}
rebuild() {
	/usr/bin/git prune --expire=now
	/usr/bin/git reflog expire --expire-unreachable=now --rewrite --all
	/usr/bin/git pack-refs --all
	/usr/bin/git repack -n -a -d -f --depth=64 --window=300 --threads=0
	/usr/bin/git prune-packed
	/usr/bin/git fsck --strict --unreachable --dangling --full --cache
}
retag() {
	LATEST="$(/usr/bin/git describe --tags --abbrev=0)"
	RELEA="$(($(echo $LATEST | cut -d . -f 1) + 0))"
	MAJOR="$(($(echo $LATEST | cut -d . -f 2) + 0))"
	MINOR="$(($(echo $LATEST | cut -d . -f 3) + 1))"
	if [ "$RELEA" = "0" ] && [ "$MAJOR" = "0" ] && [ "$MINOR" = "1" ]; then MAJOR="1"; fi
	NEWRR="v$RELEA.$MAJOR.$MINOR"
	echo "######### TAG $REPO -> $LATEST -> $NEWRR auto:sign-and-release"
	/usr/bin/git tag -s $NEWRR -m 'auto:sign-and-release'
}
clean_push() {
	if [ -e go.mod ]; then
		sh /etc/action/fmt.golang || exit 1
		go version > /dev/null 2>&1 || exit 1
		rm -rf go.mod go.sum > /dev/null 2>&1
		go mod init paepcke.de/$REPO > /dev/null 2>&1 || exit 1
		case $REPO in
		gps*) ;;
		*) sed -i '' -e 's/go 1\.20/go 1\.19/g' go.mod ;;
		esac
		GOSUMDB="sum.golang.org+033de0ae+Ac4zctda0e5eza+HJyk9SxEdh+s3Ux18htTTAD8OuAn8" go mod tidy || exit 1
	fi
	/usr/bin/git rm -r --cached .
	/usr/bin/git add .
	/usr/bin/git commit -m "auto: sync upstream / update dependencies"
	/usr/bin/git gc --quiet --auto || exit 1
	if [ ! -z "$RETAG" ]; then retag; fi
	/etc/action/git.push
}
build_project() {
	echo "###################################################################################"
	echo "### [start] [$REPO]"
	NEW="$WWW/$REPO"
	mkdir -p "$NEW" || exit 1
	cd $NEW || exit 1
	cp $BASE/.template.project.html index.html || exit 1
	if [ -e $BSD_DEV/$REPO/.apionly ]; then
		sed -i '' -e "/INSTALL/d" index.html
		sed -i '' -e "/DOWNLOAD/d" index.html
	fi
	if [ -e $BSD_DEV/$REPO/.dataonly ]; then
		sed -i '' -e "/DOCS/d" index.html
		sed -i '' -e "/INSTALL/d" index.html
		sed -i '' -e "/DOWNLOAD/d" index.html
	fi
	if [ -e $BSD_DEV/$REPO/.norelease ]; then
		sed -i '' -e "/DOWNLOAD/d" index.html
	fi
	if [ ! -e $BSD_DEV/$REPO/.github.com ]; then
		sed -i '' -e "/github/d" index.html
	fi
	if [ ! -e $BSD_DEV/$REPO/.gitlab.com ]; then
		sed -i '' -e "/gitlab/d" index.html
	fi
	if [ ! -e $BSD_DEV/$REPO/.codeberg.org ]; then
		sed -i '' -e "/codeberg/d" index.html
	fi
	if [ ! -e $BSD_DEV/$REPO/.sr.ht ]; then
		sed -i '' -e "/git.sr.ht/d" index.html
	fi
	sed -i '' -e "s/XXXPKGXXX/$REPO/g" index.html
	echo "<tr><td><a href="$REPO"><button>$REPO</button></a></td></tr>" >> $INDEX
	cd $BSD_DEV/$REPO || exit 1
	if [ "$FIXURL" == "true" ] && [ -e README.md ]; then
		goo.xurls.fix README.md || exit 1
	fi
	if [ -x .git ]; then
		. /etc/action/git.config
		if [ "$DIST" == "pnoc" ]; then clean_push; fi
		if [ "$DIST" == "bsrv" ]; then rebuild; fi
		if [ ! -z "$UPSIG" ]; then
			LATEST=$(doasgit -C $BSD_GIT/.repo/github_com_paepckehh_$REPO describe --tags --abbrev=0)
			echo "$REPO => tag: $LATEST"
			HQ_ADD_SIGNIFY=true sh /etc/action/git.sign github_com_paepckehh_$REPO $LATEST
		fi
	fi
	echo "### [done] [$REPO]"
	echo "###################################################################################"
}
action() {
	echo "## START REPO HEALTH CHECKS & CACHING"
	for REPO in $REPOS; do
		cd $BSD_DEV/$REPO && (
			if [ -e .export ] && [ -x .git ]; then
				echo -n "[$REPO] "
				/usr/bin/git gc --quiet || exit 1
			fi
		)
	done
	echo && echo "## DONE REPO HEALTH CHECKS & CACHING"
	for REPO in $REPOS; do
		cd $BSD_DEV/$REPO && if [ -e .export ]; then build_project; fi
	done
	echo "</table></div><br><br>" >> $INDEX
	echo "<a href="imp.html"><button> [impressum] & [contact] </button></a><br>" >> $INDEX
	echo "</body></html>" >> $INDEX
	cp -f $BASE/.template.imp.html $WWW/imp.html
	cp -f $BASE/.template.keys $WWW/keys/keys
	cp -f $BASE/.template.keys $WWW/paepcke.keys
	cp -f $BASE/.template.keys.hqs $WWW/keys/keys.hqs
	cp -f $BASE/.template.keys.hqs $WWW/paepcke.keys.hqs
	cp -f $BASE/.IE6RYZ-S3-DLPR3X-RH-QNPPWOXXCB $WWW/IE6RYZ-S3-DLPR3X-RH-QNPPWOXXCB
	cp -f $BASE/.IE6RYZ-S3-DLPR3X-RH-QNPPWOXXCB.signify.pub $WWW/IE6RYZ-S3-DLPR3X-RH-QNPPWOXXCB.signify.pub
	cp -f $BASE/.allowed_signers $WWW/allowed_signers
	cp -f $BASE/.allowed_signers.hqs $WWW/allowed_signers.hqs
	chown -R 0:0 $WWW
	chmod -R o=rX,g=rX,u=rX $WWW
	for PAGES in $TARGETPAGES; do
		if [ -x "$PAGES" ]; then
			cp -af $WWW/* $PAGES/
			(
				cd $PAGES && (
					if [ "$DIST" == "pnoc" ]; then clean_push; fi
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
}
setup
action
exit 0
#################################
