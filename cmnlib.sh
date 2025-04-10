#!/usr/bin/env bash

cmn::output::info() {
#
# Outputs an informational message on stdout.
# Can be called with a string argument or with a Bash heredoc.
#

	# Calling `exec` without a /command/ argument (which is the case here)
	# applies any redirection applied to it to the current shell.
	# Consequently, calling `exec <<< "${@}" feeds stdin with $@.
	# This allows the function to be called with an argument or with an
	# heredoc.
	[[ ${#} -gt 0 ]] && exec <<< "${@}"

	# Read `stdin` line by line and outputs each line formatted:
	while read -r line; do
		printf "     %b\n" "${line}"
	done
}

cmn::output::warn() {
#
# Outputs a warning message on stdout.
# Can be called with a string argument or with a Bash heredoc.
#

	# Calling `exec` without a /command/ argument (which is the case here)
	# applies any redirection applied to it to the current shell.
	# Consequently, calling `exec <<< "${@}" feeds stdin with $@.
	# This allows the function to be called with an argument or with an
	# heredoc.
	[[ ${#} -gt 0 ]] && exec <<< "${@}"

	# Read `stdin` line by line and outputs each line formatted:
	while read -r line; do
		printf " !   %b\n" "${line}"
	done
}

cmn::output::err() {
#
# Outputs an error message on stderr.
# Can be called with a string argument or with a Bash heredoc.
#

	# Calling `exec` without a /command/ argument (which is the case here)
	# applies any redirection applied to it to the current shell.
	# Consequently, calling `exec <<< "${@}" feeds stdin with $@.
	# This allows the function to be called with an argument or with an
	# heredoc.
	[[ ${#} -gt 0 ]] && exec <<< "${@}"

	# Read `stdin` line by line and outputs each line formatted:
	while read -r line; do
		printf " !!  %b\n" "${line}" >&2
	done

	if [ -n "${DEBUG}" ]; then
		cmn::output::traceback
	fi
}

cmn::output::debug() {
#
# Outputs a debug message on stdout.
# Can be called with a string argument or with a Bash heredoc.
# Only outputs when DEBUG is set!
#

	# Return ASAP if DEBUG isn't set
	[[ -z "${DEBUG}" ]] && return

	# Calling `exec` without a /command/ argument (which is the case here)
	# applies any redirection applied to it to the current shell.
	# Consequently, calling `exec <<< "${@}" feeds stdin with $@.
	# This allows the function to be called with an argument or with an
	# heredoc.
	[[ ${#} -gt 0 ]] && exec <<< "${@}"

	echo
	# Read `stdin` line by line and outputs each line formatted.
	# We also add some traceback information (filename, function and lineno)
	while read -r line; do
		printf " *   %s: %s: %s: %b\n" \
			"${BASH_SOURCE[1]}" \
			"${FUNCNAME[1]}" \
			"${BASH_LINENO[0]}" \
			"${line}"
	done
}

cmn::output::traceback() {
#
# Outputs a traceback to stderr.
#

	printf " !!  Traceback:\n" >&2

	for (( i=1; i<${#FUNCNAME[@]}; i++ )); do
		>&2 printf " !!    %s: %s: %s\n" \
			"${BASH_SOURCE[i]}" \
			"${FUNCNAME[$i]}" \
			"${BASH_LINENO[$i-1]}"
	done
}



cmn::trap::setup() {
#
# Instructs the buildpack to catch the `EXIT`, `SIGHUP`, `SIGINT`,
# `SIGQUIT`, `SIGABRT`, and `SIGTERM` signals and to call `cmn::main::fail`
# when it happens.
#

	trap cmn::main::fail EXIT SIGHUP SIGINT SIGQUIT SIGABRT SIGTERM
}

cmn::trap::teardown() {
#
# Instructs the buildpack to stop catching the `EXIT`, `SIGHUP`, `SIGINT`,
# `SIGQUIT`, `SIGABRT`, and `SIGTERM` signals.
#

	trap - EXIT SIGHUP SIGINT SIGQUIT SIGABRT SIGTERM
}



cmn::main::start() {
#
# Configures Bash options, populates a few global variables and marks the
# beginning of the buildpack.
#
# Calls `cmn::trap::setup`.
# Use this function at the beginning of the buildpack.
#

	set -o errexit
	set -o pipefail

	if [ -n "${BUILDPACK_DEBUG}" ]; then
		set -o xtrace
	fi

	build_dir="${2:-}"
	cache_dir="${3:-}"
	env_dir="${4:-}"

	base_dir="$( cd -P "$( dirname "${1}" )" && pwd )"
	buildpack_dir="$( readlink -f "${base_dir}/.." )"
	tmp_dir="$( mktemp --directory --tmpdir="/tmp" --quiet "bp-XXXXXX" )"

	cmn::output::debug <<-EOM
		build_dir:     ${build_dir}
		cache_dir:     ${cache_dir}
		env_dir:       ${env_dir}
		buildpack_dir: ${buildpack_dir}
		tmp_dir:       ${tmp_dir}
	EOM

	pushd "${build_dir}" > /dev/null

	cmn::trap::setup
}

cmn::main::end() {
#
# /!\ Not to be called directly /!\
#
# Please use `cmn::main::finish` or `cmn::main::fail` instead.
# Calls `cmn::trap::teardown`.
#

	cmn::trap::teardown

	pushd "${build_dir}" > /dev/null

	unset build_dir
	unset cache_dir
	unset env_dir
	unset base_dir
	unset buildpack_dir
	unset tmp_dir
}

cmn::main::finish() {
#
# Outputs a success message and exits with a `0` return code, thus
# instructing the platform that the buildpack ran successfully.
# Calls `cmn::main::end`.
# Use this function as the last instruction of the buildpack, when it
# succeeded.
#

	cmn::main::end
	printf "\n%b\n" "All done."
	exit 0
}

cmn::main::fail() {
#
# Outputs an error message and exits with a `1` return code, thus
# instructing the platform that the buildpack failed (and so did the
# build).
# Calls `cmn::main::end`.
# Use this function as the last instruction of the buildpack, when it
# failed.
#

	cmn::main::end
	printf "\n%b\n" "Failed." >&2
	exit 1
}



cmn::step::start() {
#
# Outputs a message marking the beginning of a buildpack step. A step is a
# group of tasks that are logically bound.
# Use this function when the step is about to start.
#

	printf "%s %b\n" "--->" "${*}"
}

cmn::step::finish() {
#
# Outputs a success message marking the end of a buildpack step.
# Use this function when the step succeeded.
#

	printf "     %b\n" "Done."
}

cmn::step::fail() {
#
# Outputs an error message marking the end of a buildpack step.
# Use this function when the step failed.
#

	printf "     %b\n" "Failed."
}



cmn::task::start() {
#
# Outputs a message marking the beginning of a buildpack task. A task is a
# single instruction, such as downloading a file, extracting an archive,...
# Use this function when the task is about to start.
#

	echo -n "     $*... "
}

cmn::task::finish() {
#
# Outputs a success message marking the end of a task.
# Use this function when the task succeeded.
#

	echo "OK."
}

cmn::task::fail() {
#
# Outputs an error message marking the end of a task.
# Calls `cmn::ouput::err` with `$1` when `$1` is set.
#

	echo "Failed."

	if [ -n "${1}" ]; then
		cmn::output::err "${1}"
	fi
}



cmn::file::check_checksum() {
#
# Computes the checksum of a file and checks that it matches the one stored in
# the reference file.
# md5, sha1 and sha256 hashing algorithm are currently supported.
#
# $1: file
# $2: checksum file
#

	local -r file="${1}"
	local -r hash_file="${2}"

	local -r hash_algo="${hash_file##*.}"
	local -r ref_hash="$( cut -d " " -f 1 < "${hash_file}" )"

	local rc=1

	case "${hash_algo}" in
		"sha1")
			shasum --algorithm 1 --check --status <<< "${ref_hash}  ${file}"
			rc="${?}"
			;;

		"sha256")
			shasum --algorithm 256 --check --status <<< "${ref_hash}  ${file}"
			rc="${?}"
			;;

		"md5")
		    md5sum --check --status <<< "${ref_hash}  ${file}"
			rc="${?}"
			;;

		*)
			rc=2
			;;
	esac

	return "${rc}"
}

cmn::file::download() {
#
# Downloads the file pointed by the given URL and stores it at the given path.
#
# $1: URL of the file to download
# $2: (opt) Path where to output the downloaded file. Defaults to /dev/stdout.
#

	local -r url="${1}"
	local -r out="${2:-"-"}"

	curl --silent --fail --retry 3 --location "${url}" --output "${out}"

	return "${?}"
}

cmn::file::download_and_check() {
#
# Downloads a file from the specified URL, stores it at the specified path.
# Also downloads the checksum from the specified URL, stores it at the
# specified path.
# Finally checks the hash of the downloaded file against the downloaded
# checksum.
#
# Calls `cmn::file::download`
# Calls `cmn::file::check_checksum`
# Calls `cmn::jobs::wait`
#
# $1: file URL
# $2: checksum URL
# $3: file path (where to store the downloaded file)
# $4: hash path (where to store the downloaded checksum file)
#

	local -r file_url="${1}"
	local -r hash_url="${2}"
	local -r file_path="${3}"
	local -r hash_path="${4}"

	local rc=1

	cmn::file::download "${file_url}" "${file_path}" &
	cmn::file::download "${hash_url}" "${hash_path}" &

	if cmn::jobs::wait; then
		cmn::file::check_checksum "${file_path}" "${hash_path}"
		rc="${?}"
	fi

	return "${rc}"
}


cmn::jobs::wait() {
#
# Waits for all child jobs running in background to finish.
# Returns the number of failed jobs (zero means they all succeeded)
#
# We use `jobs -p` to get the list of child jobs running in background.
# There might a very small risk of trying to wait for a process that would be
# already done when calling `wait` and another one taking the same pid.
# In this case, `wait` should fail, so it shouldn't be an issue.
#

	local rc=0

	while read -r pid; do
    	if ! wait "${pid}"; then
			(( rc+=1 ))
		fi
	done <<< "$( jobs -p )"

	return "${rc}"
}



cmn::str::join() {
	local -r separator="${1}"

	local res

	res="$( printf "${separator}%s" "${@}" )"
	# Remove leading separator:
	res="${res:${#separator}}"

	echo "${res}"
}



cmn::env::read() {
	local -r env_dir="${1}"
	local -r env_vars="$( cmn::env::list "${env_dir}" )"

	while read -r e; do
		local value
		value="$( cat "${env_dir}/${e}" )"

		export "${e}=${value}"
	done <<< "${env_vars}"
}

cmn::env::list() {
	local -r env_dir="${1}"

	local env_vars
	local blocklist
	local blocklist_regex

	blocklist=( "PATH" "GIT_DIR" "CPATH" "CPPATH" )
	blocklist+=( "LD_PRELOAD" "LIBRARY_PATH" "LD_LIBRARY_PATH" )
	blocklist+=( "JAVA_OPTS" "JAVA_TOOL_OPTIONS" )
	blocklist+=( "BUILDPACK_URL" "BUILD_DIR" )

	blocklist_regex="^($( cmn::str::join "|" "${blocklist[@]}" ))$"

	if [[ -d "${env_dir}" ]]; then
		# shellcheck disable=SC2010
		env_vars="$( ls "${env_dir}" \
						| grep \
							--invert-match \
							--extended-regexp \
							"${blocklist_regex}" )"
	fi

	echo "${env_vars:=""}"
}



cmn::bp::run() {
	local -r buildpack_url="${1}"
	local -r build_dir="${2}"
	local -r cache_dir="${3}"
	local -r env_dir="${4}"

	local rc=1
	local bp_dir

	if ! bp_dir="$( mktemp --directory --tmpdir="/tmp" \
						--quiet "sub_bp-XXXXXX" )"; then
		return "${rc}"
	fi

	# If the repo is not reachable, GIT_TERMINAL_PROMPT=0 allows us to fail
	# instead of asking for credentials
	if ! GIT_TERMINAL_PROMPT=0 \
			git clone --quiet --depth=1 "${buildpack_url}" "${bp_dir}" \
				2>/dev/null
	then
		rc=2
	else
		if ! "${bp_dir}/bin/compile" "${build_dir}" "${cache_dir}" "${env_dir}"
		then
			rc="${?}"
		else
			# Source `export` file if it exists:
			if [[ -f "${bp_dir}/export" ]]; then
				# shellcheck disable=SC1091
				source "${bp_dir}/export"
			fi

			# Silently remove the buildpack temporary directory:
			rm --recursive --force "${bp_dir}"

			rc=0
		fi
	fi

	return "${rc}"
}



readonly -f cmn::output::info
readonly -f cmn::output::warn
readonly -f cmn::output::err
readonly -f cmn::output::traceback

readonly -f cmn::trap::setup
readonly -f cmn::trap::teardown

readonly -f cmn::main::start
readonly -f cmn::main::end
readonly -f cmn::main::finish
readonly -f cmn::main::fail

readonly -f cmn::step::start
readonly -f cmn::step::finish
readonly -f cmn::step::fail

readonly -f cmn::task::start
readonly -f cmn::task::finish
readonly -f cmn::task::fail

readonly -f cmn::file::check_checksum
readonly -f cmn::file::download
readonly -f cmn::file::download_and_check

readonly -f cmn::str::join

readonly -f cmn::env::read
readonly -f cmn::env::list

readonly -f cmn::bp::run
