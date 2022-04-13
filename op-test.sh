#!/bin/sh
#
# Downloads the run_unit_tests.sh file from easyrsa-unit-tests repo
# and executes that - allows for disconnected testing from the easy-rsa
# repo with TravisCI.

# log
log () {
	[ "$disable_log" ] && return
	if printf '%s\n' "* $*"; then
		return
	else
		echo "printf failed"
		exit 9
	fi
} # => log ()

# clean up
clean_up () {
	if [ "$no_delete" ]; then
		log "saved final state.."
	else
		log "op-test: clean_up"
		if [ "$EASYRSA_NIX" ]; then
			[ "$keep_eut" ] || rm -f "$utest_bin"
			[ "$keep_sc" ] || rm -f "$sc_bin"
			[ "$keep_ssl" ] || rm -f "$ssl_bin"
		fi
	fi
} # => clean_up ()

# curl download and openssl hash
# wing it ..
curl_it () {
	#log "BEGIN: curl_it"
	if [ "$#" -eq 2 ]; then
		file="$1"
		hash="$2"
	else
		log "> Usage: <file> <hash>"
		return 1
	fi

	if [ "$enable_curl" ]; then
		: # ok
	else
		log "> curl disabled"
		return 0
	fi

	# valid target
	case "$file" in
	easyrsa-unit-tests.sh)
		unset -v require_hash
	;;
	shellcheck|openssl)
		require_hash=1
	;;
	*)
		log "> invalid target: $file"
		return 1
	esac

	# download
	if [ "$enable_curl" ]; then
		log "> download: ${gh_url}/${file}"
		curl -SO "${gh_url}/${file}" || \
			log "> download failed: ${file}"
	else
		log "> curl disabled"
	fi

	# hash download
	if [ "${require_hash}" ]; then
		if [ -e "${file}" ]; then
			log "> hash ${file}"
			temp_hash="$(openssl sha256 "${file}")"
			#log "temp_hash: $temp_hash"
			#log "hash     : $hash"
			if [ "$temp_hash" = "$hash" ]; then
				: # OK - hash is good
			else
				log "> hash failed: ${file}"
				return 1
			fi
		else
			log "> file missing: ${file}"
			return 1
		fi
	else
		if [ -e "${file}" ]; then
			: # ok - file is here
		else
			log "> file missing: ${file}"
			return 1
		fi
	fi
} # => curl_it ()

################################################################################

# RUN unit test
run_unit_test ()
{
	if [ "${utest_bin_ok}" ] && [ "${ssl_bin_ok}" ]; then

		# Start unit tests
		log ">>> BEGIN unit tests:"
		[ "$no_delete" ] && export SAVE_PKI=1

		if [ "${dry_run}" ]; then
			log "<<dry-run>> sh ${utest_bin} ${verb}"
			estat=1
		else
			log ">>>>>>: sh ${utest_bin} ${verb}"
			if sh "${utest_bin}" "${verb}"; then
				log "OK"
				estat=0
			else
				log "FAIL"
				estat=1
			fi
		fi
		log "<<< END unit tests:"
		unset SAVE_PKI
	else
		log "unit-test abandoned"
		estat=1
	fi
} # => run_unit_test ()

########################################

## DOWNLOAD unit-test
download_unit_test () {
	# if not present then download unit-test 
	target_file="${utest_file}"
	target_hash="${utest_hash}"
	if [ "$enable_unit_test" ]; then
		if [ -e "${ERSA_UT}/${target_file}" ]; then
			keep_eut=1
			[ -x "${ERSA_UT}/${target_file}" ] || \
				chmod +x "${ERSA_UT}/${target_file}"
			# version check
			if "${ERSA_UT}/${target_file}" version; then
				utest_bin="${ERSA_UT}/${target_file}"
				utest_bin_ok=1
				export ERSA_UTEST_CURL_TARGET=localhost
			else
				log "version check failed: ${ERSA_UT}/${target_file}"
			fi
		else
			# download and basic check
			log "curl_it ${target_file}"
			if curl_it "${target_file}" "${target_hash}"; then
				[ -x "${ERSA_UT}/${target_file}" ] || \
					chmod +x "${ERSA_UT}/${target_file}"
				# functional check - version check
				if "${ERSA_UT}/${target_file}" version; then
					utest_bin="${ERSA_UT}/${target_file}"
					utest_bin_ok=1
					export ERSA_UTEST_CURL_TARGET=online
				else
					log "version check failed: ${target_file}"
				fi
			else
				log "curl_it ${target_file} - failed"
			fi
		fi
		[ "$utest_bin_ok" ] || log "undefined: utest_bin_ok"
		log "setup unit-test - ok"
	else
		log "unit-test disabled"
	fi # => shellcheck
}
## DOWNLOAD unit-test

################################################################################

## USE shellcheck

# Run shellcheck
run_shellcheck () {
	if [ "$enable_shellcheck" ] && [ "$sc_bin_ok" ] && [ "$EASYRSA_NIX" ]; then
		# shell-check easyrsa3/easyrsa
		if [ -e easyrsa3/easyrsa ]; then
			if "${sc_bin}" -s sh -S warning -x easyrsa3/easyrsa; then
				log "shellcheck easyrsa3/easyrsa completed - ok"
			else
				log "shellcheck easyrsa3/easyrsa completed - FAILED"
			fi
		else
			log "easyrsa binary not present, not using shellcheck"
		fi

		# shell-check easyrsa-unit-tests.sh
		if [ -e easyrsa-unit-tests.sh ]; then
			if "${sc_bin}" -s sh -S warning -x easyrsa-unit-tests.sh; then
				log "shellcheck easyrsa-unit-tests.sh completed - ok"
			else
				log "shellcheck easyrsa-unit-tests.sh completed - FAILED"
			fi
		else
			log "easyrsa-unit-tests.sh binary not present, not using shellcheck"
		fi
	else
		log "shellcheck abandoned"
	fi
}
## USE shellcheck

########################################

## DOWNLOAD shellcheck
download_shellcheck () {
	# if not present then download shellcheck
	target_file="${sc_file}"
	target_hash="${sc_hash}"
	if [ "$enable_shellcheck" ] && [ "$EASYRSA_NIX" ]; then
		log "setup shellcheck"
		if [ -e "${ERSA_UT}/${target_file}" ]; then
			keep_sc=1
			[ -x "${ERSA_UT}/${target_file}" ] || \
				chmod +x "${ERSA_UT}/${target_file}"
			"${ERSA_UT}/${target_file}" -V || \
				log "version check failed: ${ERSA_UT}/${target_file}"
			sc_bin="${ERSA_UT}/${target_file}"
			sc_bin_ok=1
		else
			# download and basic check
			log "curl_it ${target_file}"
			if curl_it "${target_file}" "${target_hash}"; then
				log "curl_it ${target_file} - ok"
				[ -x "${ERSA_UT}/${target_file}" ] || \
					chmod +x "${ERSA_UT}/${target_file}"
				# functional check
				if "${ERSA_UT}/${target_file}" -V; then
					sc_bin="${ERSA_UT}/${target_file}"
					sc_bin_ok=1
				else
					log "version check failed: ${ERSA_UT}/${target_file}"
				fi
				log "shellcheck enabled"
			else
				log "curl_it ${target_file} - failed"
			fi
		fi
	fi

	## DOWNLOAD shellcheck
}

################################################################################

## DOWNLOAD openssl-3
download_opensslv3 () {
	# if not present then download and then use openssl3
	target_file="${ssl_file}"
	target_hash="${ssl_hash}"
	if [ "$enable_openssl3" ] && [ "$EASYRSA_NIX" ]; then
		if [ -e "${ERSA_UT}/${target_file}" ]; then
			keep_ssl=1
			[ -x "${ERSA_UT}/${target_file}" ] || \
				chmod +x "${ERSA_UT}/${target_file}"
			# version check 'openssl version'
			"${ERSA_UT}/${target_file}" version || \
				log "version check failed: ${ERSA_UT}/${target_file}"
			ssl_bin="${ERSA_UT}/${target_file}"
			ssl_bin_ok=1
			# Set up Easy-RSA Unit-Test for OpenSSL-v3
			export EASYRSA_OPENSSL="${ssl_bin}"
		else
			# download and basic check
			log "curl_it ${target_file}"
			if curl_it "${target_file}" "${target_hash}"; then
				log "curl_it ${target_file} - ok"
				[ -x "${ERSA_UT}/${target_file}" ] || \
					chmod +x "${ERSA_UT}/${target_file}"
				# functional check - version check 'openssl version'
				if "${ERSA_UT}/${target_file}" version; then
					ssl_bin="${ERSA_UT}/${target_file}"
					ssl_bin_ok=1
					# Set up Easy-RSA Unit-Test for OpenSSL-v3
					export EASYRSA_OPENSSL="${ssl_bin}"
				else
					log "version check failed: ${ERSA_UT}/${target_file}"
				fi
			else
				log "curl_it ${target_file} - failed"
			fi
		fi

			log "OpenSSL-v3 enabled"

	else
		if [ "$EASYRSA_NIX" ]; then
			log "System SSL enabled"
			ssl_bin="openssl"
			ssl_bin_ok=1
		else
			log "Windows, no OpenSSL-v3"
			log "System SSL enabled"
			ssl_bin="openssl"
			ssl_bin_ok=1
		fi
	fi
} # => ## DOWNLOAD openssl-3

################################################################################

	# Register clean_up on EXIT
	#trap "exited 0" 0
	# When SIGHUP, SIGINT, SIGQUIT, SIGABRT and SIGTERM,
	# explicitly exit to signal EXIT (non-bash shells)
	trap "clean_up" 1
	trap "clean_up" 2
	trap "clean_up" 3
	trap "clean_up" 6
	trap "clean_up" 15


unset -v disable_log verb enable_unit_test enable_shellcheck enable_openssl3 \
		keep_sc keep_ssl keep_eut no_delete

# Set by default
enable_unit_test=1
enable_curl=1
EASYRSA_NIX=1

while [ -n "$1" ]; do
	case "$1" in
	--no-log)			disable_log=1 ;;
	'')					verb='-v' ;;
	-v)					verb='-v' ;;
	-vv)				verb='-vv' ;;
	-sc)				enable_shellcheck=1 ;;
	-o3)				enable_openssl3=1 ;;
	-dr)				dry_run=1 ;;
	-nt|--no-test)		unset -v enable_unit_test ;;
	-nc|--no-curl)		unset -v enable_curl ;;
	-nd|--no-delete)	no_delete=1 ;;
	-w|--windows)		export EASYRSA_WIN=1; unset -v EASYRSA_NIX ;;
	*)
		log "Unknown option: $1"
		exit 9
	esac
	shift
done

log "Easy-RSA Unit Tests:"

# Layout
ERSA_UT="${PWD}"

# Sources
gh_url='https://raw.githubusercontent.com/OpenVPN/easyrsa-unit-tests/master'

utest_file='easyrsa-unit-tests.sh'
unset -v utest_bin utest_bin_ok
utest_hash='no-hash'

sc_file='shellcheck'
unset -v sc_bin sc_bin_ok
sc_hash='SHA256(shellcheck)= f4bce23c11c3919c1b20bcb0f206f6b44c44e26f2bc95f8aa708716095fa0651'

ssl_file='openssl'
unset -v ssl_bin ssl_bin_ok
ssl_hash='SHA256(openssl)= bc4a5882bad4f51e6d04c25877e1e85ad86f14c5f6e078dd9c02f9d38f8791be'

# Here we go ..

download_shellcheck
download_opensslv3
download_unit_test

run_shellcheck
run_unit_test

# No trap required..
clean_up

################################################################################

log "estat: $estat ${dry_run:+<<dry run>>}"
exit $estat

# vim: no
