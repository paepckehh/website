#!/bin/sh
setup() {
	# freebsd: sudo pkg install git go yq
	# linux: sudo apt install git go yq
	# macos: brew install git go yq
	go version || exit 1
	git version || exit 1
	export GOPROXY="proxy.golang.org"
	export GOSUMDB="sum.golang.org+033de0ae+Ac4zctda0e5eza+HJyk9SxEdh+s3Ux18htTTAD8OuAn8"
	export MYDEV="/Users/mpp/dev"
	export BASE="$MYDEV/website"
	export WWW="$BASE/www"
	export INDEX=$WWW/index.html
	export LIVE="/.worker/gate/var/squid/reports"
	export TARGETPAGES="$MYDEV/paepckehh.github.io $MYDEV/pages"
	export UUID="$(uuidgen)"
	export REPOS="$(cd $MYDEV && ls -I | grep -v action)"
	export MYKEYS="~/.keys"
	if [ -z "$REPOS" ] || [ ! -x "$BASE" ]; then echo "unable to access repo" && exit 1; fi
	sudo rm -rf $WWW || exit 1
	mkdir -p $WWW || exit 1
	cp -f $BASE/.template.index.html $INDEX || exit 1
}
rebuild() {
	git prune --expire=now
	git reflog expire --expire-unreachable=now --rewrite --all
	git pack-refs --all
	git repack -n -a -d -f --depth=64 --window=300 --threads=0
	git prune-packed
	git fsck --strict --unreachable --dangling --full --cache
}
retag() {
	LATEST="$(git describe --tags --abbrev=0)"
	RELEA="$(($(echo $LATEST | cut -d . -f 1) + 0))"
	MAJOR="$(($(echo $LATEST | cut -d . -f 2) + 0))"
	MINOR="$(($(echo $LATEST | cut -d . -f 3) + 2))"
	if [ "$RELEA" = "0" ] && [ "$MAJOR" = "0" ] && [ "$MINOR" = "1" ]; then MAJOR="1"; fi
	NEWRR="v$RELEA.$MAJOR.$MINOR"
	echo "######### TAG $REPO -> $LATEST -> $NEWRR auto:sign-and-release"
	git tag -s $NEWRR -m 'auto:sign-and-release'
}
git_action() {
	if [ -z "$GITACTION" ]; then echo "no git action set" && exit 1; fi
	export REPONAME="${PWD##*/}"
	export GIT_SSH_COMMAND="ssh -4akxy \
			-i ~/.ssh/id_ed25519 \
			-m hmac-sha2-512-etm@openssh.com \
			-c chacha20-poly1305@openssh.com \
			-o MACs=hmac-sha2-512-etm@openssh.com \
			-o Ciphers=chacha20-poly1305@openssh.com \
			-o KexAlgorithms=curve25519-sha256 \
			-o PubkeyAcceptedKeyTypes=ssh-ed25519 \
			-o UserKnownHostsFile=~/.ssh/known_hosts \
			-o StrictHostKeyChecking=yes \
			-o UpdateHostKeys=no \
			-o ServerAliveInterval=120 \
			-o ServerAliveCountMax=3 \
			-o TCPKeepAlive=no \
			-o Tunnel=no \
			-o VisualHostKey=no \
			-o Compression=no \
			-o VerifyHostKeyDNS=no \
			-o AddKeysToAgent=no \
			-o ForwardAgent=no \
			-o ClearAllForwardings=yes \
			-o IdentitiesOnly=yes \
			-o IdentityAgent=none"
	export ALLOWED_CIPHERS_TLS13=TLS_CHACHA20_POLY1305_SHA256
	export ALLOWED_KEX_CURVES=X25519
	export CERT_FILE=/etc/ssl/external_trust.pem
	export SSL_CERT_FILE=$CERT_FILE
	export GIT_SSL_CAINFO=$CERT_FILE
	export GIT_SSL_VERSION=tlsv1.3
	export CURLOPT_SSL_CURVES_LIST=$ALLOWED_KEX_CURVES
	export CURLOPT_SSL_CAPATH=$CERT_FILE
	export CURLOPT_SSL_CAINFO=$CERT_FILE
	export CURLOPT_SSL_PROXY_SSL_CAINFO=$CERT_FILE
	export CURLOPT_SSL_CAPATH="/etc/ssl/externa;_trust.pem"
	export GIT_HTTP_USER_AGENT=git
	export GCMD="git"
	export GITCMD="$GCMD $GITACTION"
	export REPOS="codeberg.org gitlab.com sr.ht github.com"
	unset HTTPS_PROXY HTTP_PROXY
	for DOM in $REPOS; do
		if [ -e ".$DOM" ]; then
			ID="git" && TARGETID=":paepcke" &&ADDR="$DOM" && SUFFIX=".git"
			case $DOM in
			github.com) TARGETID=":paepckehh" ;;
			codeberg.org) continue ;;
			gitlab.com) continue ;;
			sr.ht) continue ;;
			esac
			URL="$ID@$ADDR$TARGETID/$REPONAME$SUFFIX"
			echo "########################################################################"
			echo "$URL"
			git remote rm origin
			git remote add origin $URL
			git fetch
			git branch --set-upstream-to=origin/main main
			git rebase --skip 
			git $GITACTION
		fi
	done
}
git_push() {
	GITACTION="push --all --prune --force" git_action
}
git_push_tags() {
	GITACTION="push --prune --force --tags" git_action
}
git_pull() {
	GITACTION="pull -ff --prune --force" git_action
}
clean_push() {
	if [ -x .git ]; then
		git_pull
		git_push
	fi
	if [ -e go.mod ]; then
		gofmt -s -w -d . || exit 1
		go version >/dev/null 2>&1 || exit 1
		rm -rf go.mod go.sum >/dev/null 2>&1
		go mod init paepcke.de/$REPO || exit 1
		go mod tidy -go=1.21
		sed -i '' -e '/^toolchain/d' go.mod
		if [ -w .github/workflows/golang.yml ]; then 
			yq -i '.jobs.build.strategy.matrix.go-version = [1.21]' .github/workflows/golang.yml
		fi
		GOSUMDB="sum.golang.org+033de0ae+Ac4zctda0e5eza+HJyk9SxEdh+s3Ux18htTTAD8OuAn8" go mod tidy || exit 1
	fi
	git rm -r --cached .
	git add .
	git commit -S -m "auto: sync upstream / update dependencies"
	git gc --quiet --auto || exit 1
	if [ ! -z "$RETAG" ]; then retag; fi
	git_push
	git_push_tags
}
build_project() {
	echo "###################################################################################"
	echo "### [start] [$REPO]"
	NEW="$WWW/$REPO"
	mkdir -p "$NEW" || exit 1
	cd $NEW || exit 1
	if [ -e .internal ]; then return; fi
	cp $BASE/.template.project.html index.html || exit 1
	if [ -e $MYDEV/$REPO/.apionly ]; then
		sed -i '' -e "/INSTALL/d" index.html
		sed -i '' -e "/DOWNLOAD/d" index.html
	fi
	if [ -e $MYDEV/$REPO/.dataonly ]; then
		sed -i '' -e "/DOCS/d" index.html
		sed -i '' -e "/INSTALL/d" index.html
		sed -i '' -e "/DOWNLOAD/d" index.html
	fi
	if [ -e $MYDEV/$REPO/.norelease ]; then
		sed -i '' -e "/DOWNLOAD/d" index.html
	fi
	if [ ! -e $MYDEV/$REPO/.github.com ]; then
		sed -i '' -e "/github/d" index.html
	fi
	if [ ! -e $MYDEV/$REPO/.gitlab.com ]; then
		sed -i '' -e "/gitlab/d" index.html
	fi
	if [ ! -e $MYDEV/$REPO/.codeberg.org ]; then
		sed -i '' -e "/codeberg/d" index.html
	fi
	if [ ! -e $MYDEV/$REPO/.sr.ht ]; then
		sed -i '' -e "/git.sr.ht/d" index.html
	fi
	sed -i '' -e "s/XXXPKGXXX/$REPO/g" index.html
	echo "<tr><td><a href="$REPO"><button>$REPO</button></a></td></tr>" >>$INDEX
	cd $MYDEV/$REPO || exit 1
	if [ ! -z "$FIXURL" ] && [ -e README.md ]; then goo.xurls.fix README.md || exit 1; fi
	if [ -x .git ]; then
		git config core.bare false
		git config pull.ff only
		git config commit.gpgsign true
		git config user.name "Paepcke, Michael "
		git config user.email "git@paepcke.de"
		git config user.signingkey "~/.ssh/id_ed25519.pub"
		git config gpg.format "ssh"
		git config gpg.ssh.allowedSignersFile "~/.ssh/allowed_signers"
		git config core.sshCommand "ssh -4akxy -i ~/.ssh/id_ed25519 -m hmac-sha2-512-etm@openssh.com -c chacha20-poly1305@openssh.com -o MACs=hmac-sha2-512-etm@openssh.com -o Ciphers=chacha20-poly1305@openssh.com -o KexAlgorithms=curve25519-sha256 -o PubkeyAcceptedKeyTypes=ssh-ed25519 -o UserKnownHostsFile=~/.ssh/known_hosts -o StrictHostKeyChecking=yes -o UpdateHostKeys=no -o ServerAliveInterval=120 -o ServerAliveCountMax=3 -o TCPKeepAlive=no -o Tunnel=no -o VisualHostKey=no -o Compression=no -o VerifyHostKeyDNS=no -o AddKeysToAgent=no -o ForwardAgent=no -o ClearAllForwardings=yes -o IdentitiesOnly=yes -o IdentityAgent=none"
		rebuild
		clean_push
	fi
	echo "### [done] [$REPO]"
	echo "###################################################################################"
}
action() {
	echo "## START REPO HEALTH CHECKS & CACHING"
	for REPO in $REPOS; do
		cd $MYDEV/$REPO && (
			if [ -e .export ] && [ -x .git ]; then
				echo "[$REPO] "
				git gc --quiet || exit 1
			fi
		)
	done
	echo && echo "## DONE REPO HEALTH CHECKS & CACHING"
	for REPO in $REPOS; do
		cd $MYDEV/$REPO && if [ -e .export ]; then build_project; fi
	done
	echo "</table></div><br><br>" >>$INDEX
	echo -n '<a href="https://infosec.exchange/@paepcke"> <button> [social] [news] [blog] </button> </a> ' >>$INDEX
	echo -n '<a href="https://github.com/paepckehh"> <button> [github.com] </button> </a> ' >>$INDEX
	echo -n '<a href="imp.html"> <button> [contact] [keys] [impressum] </button> </a> ' >>$INDEX
	echo "<br>" >>$INDEX
	echo "</body></html>" >>$INDEX
	mkdir -p $WWW/contact
	cp -f $BASE/.template.imp.html $WWW/contact/index.html
	cp -f $BASE/.template.imp.html $WWW/imp.html
	cp -f $BASE/.template.keys $WWW/keys/keys
	cp -f $BASE/.template.keys $WWW/paepcke.keys
	cp -f $BASE/.template.keys.hqs $WWW/keys/keys.hqs
	cp -f $BASE/.template.keys.hqs $WWW/paepcke.keys.hqs
	cp -f $BASE/.IE6RYZ-S3-DLPR3X-RH-QNPPWOXXCB $WWW/IE6RYZ-S3-DLPR3X-RH-QNPPWOXXCB
	cp -f $BASE/.IE6RYZ-S3-DLPR3X-RH-QNPPWOXXCB.signify.pub $WWW/IE6RYZ-S3-DLPR3X-RH-QNPPWOXXCB.signify.pub
	cp -f $BASE/.allowed_signers $WWW/allowed_signers
	cp -f $BASE/.allowed_signers.hqs $WWW/allowed_signers.hqs
	# sudo chown -R 0:0 $WWW
	# sudo chmod -R o=rX,g=rX,u=rX $WWW
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
		rm -rf $LIVE/www.$UUID >/dev/null 2>&1
	fi
}
setup
action
exit 0
#################################
