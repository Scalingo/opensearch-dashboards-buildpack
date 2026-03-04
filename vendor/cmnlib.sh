#!/usr/bin/env bash

_cmn__read_lines() {
#
## Internal only
#
# Redirects input to stdin, line by line.
# This allows the `cmn::ouput::` functions to support heredoc.
#

	if (($#)); then
		printf '%s\n' "$@"
	elif [[ ! -t 0 ]]; then
		# stdin is not a terminal, we can safely call `cat` without arguments.
		# Removing this conditional will make `cat` wait for an input on stdin,
		# which will never happend, hence causing the script to hang forever.
		#
		# This redirects stdin to stdout.
		cat
	fi
}

_cmn__output_emit() {
#
## Internal only
#
# Reads input line by line thanks to `_cmn__read_lines`
# and outputs each line formatted on the appropriate file descriptor.
#

	local -r prefix="${1}"; shift
	# Use 1 for stdout, 2 for stderr
	# Defaults to stdout:
	local -r fd="${1:-1}"
	shift || true

	while IFS= read -r line; do
		printf '%s%s\n' "${prefix}" "${line}" >&"${fd}"
	done < <(_cmn__read_lines "$@")
}

_cmn__main_err() {
#
## Internal only
#
# Handler for unmanaged errors.
# Please use `cmn::main::finish` or `cmn::main::fail` instead.
#

	# We don't want to be caught in an err loop:
	# so stop trapping ERR ASAP:
	set +o errexit
	trap - ERR

	local -r code="${1:-1}"
	local -r cmd="${2:-""}"

	cmn::task::fail

	cmn::output::err <<-EOM
	Caught Error:
	  Command: ${cmd}
	     Exit: ${code}
	EOM

	cmn::output::traceback

	exit "${code}"
}

_cmn__main_end() {
#
## Internal only
#
# Handler for EXIT signal.
# Please use `cmn::main::finish` or `cmn::main::fail` instead.
#

	_cmn__trap_teardown

	# Ensure we are back in build_dir:
	[[ -n "${build_dir:-}" && -d "${build_dir}" ]] \
		&& pushd "${build_dir}" > /dev/null || true

	# Remove tmp_dir:
	[[ -n "${tmp_dir:-}" && -d "${tmp_dir}" ]] \
		&& rm -rf -- "${tmp_dir}" || true
}

_cmn__trap_setup() {
#
## Internal only
#
# Instructs the buildpack to catch the `SIGHUP`, `SIGINT`, `SIGQUIT`,
# `SIGABRT`, and `SIGTERM` signals and to call `cmn::main::fail`
# when it happens.
# Also instructs the buildpack to catch `EXIT` and to call `_cmn__main_end`
# when it happens.
#

	trap '_cmn__main_err $? "$BASH_COMMAND"' ERR
	trap '_cmn__main_err 129 "SIGHUP"'  HUP
	trap '_cmn__main_err 130 "SIGINT"'  INT
	trap '_cmn__main_err 131 "SIGQUIT"' QUIT
	trap '_cmn__main_err 134 "SIGABRT"' ABRT
	trap '_cmn__main_err 143 "SIGTERM"' TERM

	trap "_cmn__main_end" EXIT
}

_cmn__trap_teardown() {
#
## Internal only
#
# Instructs the buildpack to stop catching the `EXIT`, `SIGHUP`, `SIGINT`,
# `SIGQUIT`, `SIGABRT`, and `SIGTERM` signals.
#

	trap - EXIT ERR HUP INT QUIT ABRT TERM
}



cmn::output::info() {
#
# Outputs an informational message on stdout.
# Can be called with a string argument or with a Bash heredoc.
#

	local -r prefix="    "
	_cmn__output_emit "${prefix}" 1 "${@}"
}

cmn::output::warn() {
#
# Outputs a warning message on stdout.
# Can be called with a string argument or with a Bash heredoc.
#

	local -r prefix=" !  "
	_cmn__output_emit "${prefix}" 1 "${@}"
}

cmn::output::err() {
#
# Outputs an error message on stderr.
# Can be called with a string argument or with a Bash heredoc.
#

	local -r prefix=" !! "
	_cmn__output_emit "${prefix}" 2 "${@}"

	if [ -n "${_CMN_DEBUG_:-}" ]; then
		cmn::output::traceback
	fi
}

# shellcheck disable=2120
cmn::output::debug() {
#
# Outputs a debug message on stdout.
# Can be called with a string argument or with a Bash heredoc.
# Only outputs when _CMN_DEBUG_ is set!
#
# Setting _CMN_DEBUG_ should be reserved for cmnlib itself,
# or when debugging buildpacks.
#

	# Return ASAP if _CMN_DEBUG_ isn't set
	[[ -z "${_CMN_DEBUG_:-}" ]] && return

	while IFS= read -r line; do
		printf " *  %s: %s: %s: %s\n" \
			"${BASH_SOURCE[1]}" \
			"${FUNCNAME[1]}" \
			"${BASH_LINENO[0]}" \
			"${line}"
	done < <( _cmn__read_lines "${@}" )
}

cmn::output::traceback() {
#
# Outputs a traceback to stderr.
#

	printf " !! Traceback:\n" >&2

	for (( i=1; i<${#FUNCNAME[@]}; i++ )); do
		>&2 printf " !!   %s: %s: %s\n" \
			"${BASH_SOURCE[i]}" \
			"${FUNCNAME[$i]}" \
			"${BASH_LINENO[$i-1]}"
	done
}



cmn::main::start() {
#
# Configures Bash options, populates a few global variables and marks the
# beginning of the buildpack.
#
# Use this function at the beginning of the buildpack.
#

	set -o errexit -o errtrace -o pipefail

	if [[ -n "${BUILDPACK_DEBUG:-}" ]]; then
		set -o xtrace
	fi

	build_dir="${2:-}"
	cache_dir="${3:-}"
	env_dir="${4:-}"

	base_dir="$( cd -P "$( dirname "${1}" )" && pwd )"
	buildpack_dir="$( readlink -f "${base_dir}/.." )"
	tmp_dir="$( mktemp --directory --tmpdir="/tmp" --quiet "bp-XXXXXX" )"

	readonly build_dir
	readonly cache_dir
	readonly env_dir
	readonly base_dir
	readonly buildpack_dir
	readonly tmp_dir

	cmn::output::debug <<-EOM
		build_dir:     ${build_dir}
		cache_dir:     ${cache_dir}
		env_dir:       ${env_dir}
		buildpack_dir: ${buildpack_dir}
		tmp_dir:       ${tmp_dir}
	EOM

	pushd "${build_dir}" > /dev/null

	_cmn__trap_setup
}

cmn::main::finish() {
#
# Outputs a success message and exits with a `0` return code, thus
# instructing the platform that the buildpack ran successfully.
#
# Use this function as the last instruction of the buildpack, when it
# succeeded.
#

	printf "\n%s\n" "All done."
	exit 0
}


cmn::main::fail() {
#
# Outputs an error message if given and exits with the given return code, thus
# instructing the platform that the buildpack failed (and so did the
# build).
#
# When no return code is given, defaults to 1.
#
# Use this function to end the buildpack, when it encountered an unrecoverable
# failure.
#

	local -r code="${1:-1}"
	shift

	cmn::task::fail
	cmn::output::err "${@}"

	exit "${code}"
}

cmn::step::start() {
#
# Outputs a message marking the beginning of a buildpack step. A step is a
# group of tasks that are logically bound.
# Use this function when the step is about to start.
#

	printf -- "--> %s\n" "${*}"
}



cmn::task::start() {
#
# Outputs a message marking the beginning of a buildpack task. A task is a
# single instruction, such as downloading a file, extracting an archive,...
# Use this function when the task is about to start.
#

	_CMN_IN_TASK_="yes"
	printf -- "    %s... " "$*"
}

cmn::task::finish() {
#
# Outputs a success message marking the end of a task.
# Use this function when the task succeeded.
#

	if [[ -n "${_CMN_IN_TASK_}" ]]; then
		printf -- "%s\n" "OK."
		unset _CMN_IN_TASK_
	fi
}

cmn::task::fail() {
#
# Outputs an error message marking the end of a task.
# Calls `cmn::ouput::err` with `$1` when `$1` is set.
#

	if [[ -n "${_CMN_IN_TASK_}" ]]; then
		printf -- "%s\n" "Failed."
		unset _CMN_IN_TASK_
	fi

	if [[ -n "${1}" ]]; then
		cmn::output::err "${1}"
	fi
}



cmn::file::validate_checksum() {
#
# Computes the checksum of a file and checks that it matches the one stored in
# the reference file.
# md5, sha1, sha256, and sha512 hashing algorithm are currently supported.
#
# $1: file
# $2: checksum file
#

	local -r file="${1}"
	local -r hash_file="${2}"

	local -r hash_algo="${hash_file##*.}"
	local ref_hash

	if ! read -r ref_hash _ < "${hash_file}"; then
		return 2
	fi

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

		"sha512")
			shasum --algorithm 512 --check --status <<< "${ref_hash}  ${file}"
			rc="${?}"
			;;

		"md5")
			md5sum --check --status <<< "${ref_hash}  ${file}"
			rc="${?}"
			;;

		*)
			rc=3
			;;
	esac

	cmn::output::debug <<-EOM
		file:      ${file}
		hash_file: ${hash_file}
		hash_algo: ${hash_algo}
		ref_hash:  ${ref_hash}
		result:    ${rc}
	EOM

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

	cmn::output::debug <<-EOM
		Downloading "${url}" and saving to "${out}".
	EOM

	curl --silent --fail --location \
		--retry 3 --retry-delay 10 --retry-connrefused \
		--connect-timeout 10 --max-time 300 \
		--output "${out}" \
		"${url}"

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
		cmn::file::validate_checksum "${file_path}" "${hash_path}"
		rc="${?}"
	fi

	return "${rc}"
}


cmn::jobs::wait() {
#
# Waits for all child jobs running in background to finish.
# Returns the number of failed jobs (zero means they all succeeded)
#
# We use `jobs -pr` to get the list of child jobs running in background.
# There might a very small risk of trying to wait for a process that would be
# already done when calling `wait` and another one taking the same pid.
# In this case, `wait` should fail, so it shouldn't be an issue.
#

	local rc=0
	local pid

	while read -r pid; do
		# If $pid is empty, skip to next loop item:
		[[ -z "${pid}" ]] && continue

		if ! wait "${pid}"; then
			(( rc+=1 ))
		fi
	done < <( jobs -pr )

	return "${rc}"
}



cmn::str::join() {
#
# Joins all items into one string, using the given separator as separator.
#

	local -r separator="${1}"
	shift

	local res=""
	local s

	for s in "${@}"; do
		res+="${separator}${s}"
	done

	# Remove leading separator:
	res="${res:${#separator}}"

	printf "%s" "${res}"
}



cmn::env::read() {
#
# Exports configuration variables of a buildpack's ENV_DIR to environment
# variables.
#
# Only configuration variables which names pass the positive pattern and don't
# match the negative pattern are exported.
#

	local -r env_dir="${1}"
	local e
	local value

	while IFS= read -r e; do
		# Read env var value from file:
		value="$( <"${env_dir}/${e}" )"
		# Remove potential ending new line:
		value="${value%$'\n'}"
		# Export the env var:
		export "${e}=${value}"
	done < <(cmn::env::list "${env_dir}")
}

cmn::env::list() {

	local -r env_dir="${1}"
	local -a blocklist=( PATH GIT_DIR CPATH CPPATH )
	blocklist+=( LD_PRELOAD LIBRARY_PATH LD_LIBRARY_PATH )
	blocklist+=( JAVA_OPTS JAVA_TOOL_OPTIONS )
	blocklist+=( BUILDPACK_URL BUILD_DIR )

	[[ -d "${env_dir}" ]] || return 0
	
	local -r block_re="^($( cmn::str::join '|' "${blocklist[@]}" ))$"

	local f
	local name

	# List all content of env_dir:
	for f in "${env_dir}"/*; do
		# Skip item if not a file:
		[[ -f "${f}" ]] || continue

		# Keep file name only
		# For example: f="/app/env/MY_VAR" --> name="MY_VAR"
		name="${f##*/}"

		# Skip item if matching the regexp:
		[[ "${name}" =~ ${block_re} ]] && continue
		
		printf '%s\n' "${name}"
	done
}



cmn::bp::run() {
	local -r buildpack_url="${1}"
	local -r build_dir="${2}"
	local -r cache_dir="${3}"
	local -r env_dir="${4}"

	local rc=0
	local bp_dir

	if ! bp_dir="$( mktemp --directory --tmpdir="/tmp" \
			--quiet "sub_bp-XXXXXX" )"
	then
		rc=1
	else
		# If the repo is not reachable, GIT_TERMINAL_PROMPT=0 allows us to fail
		# instead of asking for credentials
		GIT_TERMINAL_PROMPT=0 \
		git clone --quiet --depth=1 "${buildpack_url}" "${bp_dir}" \
			2>/dev/null \
			|| cmn::main::fail "${?}"

		# Runs the buildpack:
		"${bp_dir}/bin/compile" "${build_dir}" "${cache_dir}" "${env_dir}" \
			|| cmn::main::fail "${?}"

		# Source `export` file if it exists:
		if [[ -f "${bp_dir}/export" ]]; then
			# shellcheck disable=SC1091
			source "${bp_dir}/export"
		fi

		# We really don't want this step to be blocking or causing errors:
		[[ -n "${bp_dir:-}" && -d "${bp_dir}" ]] \
			&& rm -rf -- "${bp_dir}" || true
	fi

	return "${rc}"
}



readonly -f cmn::output::info
readonly -f cmn::output::warn
readonly -f cmn::output::err
readonly -f cmn::output::debug
readonly -f cmn::output::traceback

readonly -f cmn::main::start
readonly -f cmn::main::finish
readonly -f cmn::main::fail

readonly -f cmn::step::start

readonly -f cmn::task::start
readonly -f cmn::task::finish
readonly -f cmn::task::fail

readonly -f cmn::file::validate_checksum
readonly -f cmn::file::download
readonly -f cmn::file::download_and_check

readonly -f cmn::str::join

readonly -f cmn::env::read
readonly -f cmn::env::list

readonly -f cmn::bp::run

readonly -f _cmn__read_lines
readonly -f _cmn__output_emit
readonly -f _cmn__main_err
readonly -f _cmn__main_end
readonly -f _cmn__trap_setup
readonly -f _cmn__trap_teardown
