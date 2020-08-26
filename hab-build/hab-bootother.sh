#!/bin/bash

# Configures and executes Habitat plan build on a temporary Linux system

# Install Habitat from On-Prem location
set -eou pipefail

min_size=2000000

if [[ $(df -P / | grep -v Avail | awk -F ' ' '{print $4}') -lt $min_size ]] ;
then
logger -s "Insuffficient disk space. Habitat not installed"
exit 1
fi

# If the variable `$DEBUG` is set, then print the shell commands as we execute.
if [ -n "${DEBUG:-}" ]; then set -x; fi

export HAB_LICENSE="accept"
# Add On-premises Fileserver URL for tar.gz here
root_url="https://artifactory-am2.devops.aig.net/artifactory/aigchef/habitat"
# This will pull latest from public packages.chef.io if not using onprem repo.
# Has also been tested to work with Artifactoy if the 'lastest' folder exists and,
# the version number isn't in the name of the tar file
version="latest"
# You can point this to On-premises builder
bldr_url="http://plgsascs4324007.r1-core.r1.aig.net"

# Adding to ENV permanently
if ! $(grep -q HAB_BLDR_URL /etc/environment) ;
then
  echo HAB_BLDR_URL=$bldr_url >> /etc/environment
fi

if ! $(grep -q HAB_LICENSE /etc/environment) ;
then
  echo HAB_LICENSE=accept >> /etc/environment
fi

if ! $(grep -q HAB_ORIGIN /etc/environment) ;
then
  echo HAB_ORIGIN=aig >> /etc/environment
fi
# The channel you want the service to watch.
channel="stable"
# Comma separated list of packaged to load.
packages=("aig/effortless")

main() {
  # Use stable Bintray channel by default
  # channel="stable"

  # Parse command line flags and options.
  while getopts "b:c:hv:r:p:" opt; do
    case "${opt}" in
      b)
        bldr_url="${OPTARG}"
        ;;
      c)
        channel="${OPTARG}"
        ;;
      h)
        print_help
        exit 0
        ;;
      v)
        version="${OPTARG}"
        ;;
      r)
        root_url="${OPTARG}"
        ;;
      p)
        packages="${OPTARG}"
        ;;
      \?)
        echo "" >&2
        print_help >&2
        exit_with "Invalid option" 1
        ;;
    esac
  done

  info "Installing Habitat 'hab' program at AIG"
  create_workdir
  download_hab_from_aig_artifactory
  extract_archive
  install_hab
  print_hab_version
  info "Installation of Habitat 'hab' program complete."
}

print_help() {
  need_cmd cat
  need_cmd basename

  local _cmd
  _cmd="$(basename "${0}")"
  cat <<USAGE
${_cmd}
Installs the Habitat 'hab' program at AIG.
USAGE:
    ${_cmd} [FLAGS]
FLAGS:
    -b    Specificy a custom builder URL (default: https://bldr.habitat.sh)
    -c    A channel to deploy the supervisor and optional packages from
    -h    Prints help information
    -o    The origin to deploy optional packages from
    -p    Optional packages/services to install, comma delimited.
    -r    The root URL of the binary store
    -v    A version of the supervisor to deploy (default: Latest)
ENVIRONMENT VARIABLES:
     SSL_CERT_FILE   allows you to verify against a custom cert such as one
                     generated from a corporate firewall
USAGE
}

useradd hab
usermod -aG hab hab


load_hab_packages() {
  for pkg in $(echo "$packages" | sed "s/,/ /g")
  do
    hab svc load "$pkg" --channel "$channel" --strategy at-once -u "$bldr_url"
  done
}

download_hab_from_aig_artifactory() {
  need_cmd mv

  local url

  get_target

  url="${root_url}/${version}/hab-${target}.tar.gz"
  dl_file "${url}" "${workdir}/hab-${target}.tar.gz"
  archive="hab-${target}.tar.gz"
  mv -v "${workdir}/hab-${target}.tar.gz" "${archive}"
}

get_target() {
# We can determine kernel major version automatically.
# At The current customer, we've named the files differently so this doesn't match whats on packages.chef.io

  kernel="$(uname -r)"
  kernel="${kernel:0:1}"

  if [ "$kernel" -eq 3 ]
  then
    target="linux"
  elif [ "$kernel" -eq 2 ]
  then
    target="linux2"
  else
    warn "Not a supported kernel"
  fi
}

extract_archive() {
  need_cmd sed

  info "Extracting ${archive}"

  need_cmd zcat
  need_cmd tar

  archive_dir="${archive%.tar.gz}"
  mkdir "${archive_dir}"
  zcat "${archive}" | tar --extract --directory "${archive_dir}" --strip-components=1
}

install_hab() {
  local _ident="core/hab"

  info "Installing Habitat package using temporarily downloaded hab"
  # NOTE: For people (rightly) wondering why we download hab only to use it
  # to install hab from Builder, the main reason is because it allows /bin/hab
  # to be a binlink, meaning that future upgrades can be easily done via
  # hab pkg install core/hab -bf and everything will Just Work. If we put
  # the hab we downloaded into /bin, then future hab upgrades done via hab
  # itself won't work - you'd need to run this script every time you wanted
  # to upgrade hab, which is not intuitive. Putting it into a place other than
  # /bin means now you have multiple copies of hab on your system and pathing
  # shenanigans might ensue. Rather than deal with that mess, we do it this
  # way.
  "${archive_dir}/hab" pkg install --binlink --force --channel "stable" --url "$bldr_url" "$_ident"
}

create_workdir() {
  need_cmd mktemp
  need_cmd rm
  need_cmd mkdir

  if [ -n "${TMPDIR:-}" ]; then
    local _tmp="${TMPDIR}"
  elif [ -d /var/tmp ]; then
    local _tmp=/var/tmp
  else
    local _tmp=/tmp
  fi

  workdir="$(mktemp -d -p "$_tmp" 2> /dev/null || mktemp -d "${_tmp}/hab.XXXX")"
  # Add a trap to clean up any interrupted file downloads
  # shellcheck disable=SC2154
  trap 'code=$?; rm -rf $workdir; exit $code' INT TERM EXIT
  cd "${workdir}"
}

print_hab_version() {
  need_cmd hab

  info "Checking installed hab version"
  hab --version
}

need_cmd() {
  if ! command -v "$1" > /dev/null 2>&1; then
    exit_with "Required command '$1' not found on PATH" 127
  fi
}

info() {
  echo "--> aig-hab-install: $1"
}

warn() {
  echo "xxx aig-hab-install: $1" >&2
}

exit_with() {
  warn "$1"
  exit "${2:-10}"
}

_array_contains() {
  local e
  for e in "${@:2}"; do
    if [[ "$e" == "$1" ]]; then
      return 0
    fi
  done
  return 1
}

dl_file() {
  local _url="${1}"
  local _dst="${2}"
  local _code
  local _wget_extra_args=""
  local _curl_extra_args=""

  # Attempt to download with wget, if found. If successful, quick return
  if command -v wget > /dev/null; then
    info "Downloading via wget: ${_url}"

    if [ -n "${SSL_CERT_FILE:-}" ]; then
      wget ${_wget_extra_args:+"--ca-certificate=${SSL_CERT_FILE}"} -q -O "${_dst}" "${_url}"
    else
      wget -q -O "${_dst}" "${_url}"
    fi

    _code="$?"

    if [ $_code -eq 0 ]; then
      return 0
    else
      local _e="wget failed to download file, perhaps wget doesn't have"
      _e="$_e SSL support and/or no CA certificates are present?"
      warn "$_e"
    fi
  fi

  # Attempt to download with curl, if found. If successful, quick return
  if command -v curl > /dev/null; then
    info "Downloading via curl: ${_url}"

    if [ -n "${SSL_CERT_FILE:-}" ]; then
      curl ${_curl_extra_args:+"--cacert ${SSL_CERT_FILE}"} -sSfL "${_url}" -o "${_dst}"
    else
      curl -sSfL "${_url}" -o "${_dst}"
    fi

    _code="$?"

    if [ $_code -eq 0 ]; then
      return 0
    else
      local _e="curl failed to download file, perhaps curl doesn't have"
      _e="$_e SSL support and/or no CA certificates are present?"
      warn "$_e"
    fi
  fi

  # If we reach this point, wget and curl have failed and we're out of options
  exit_with "Required: SSL-enabled 'curl' or 'wget' on PATH with" 6
}

main "$@" || exit 99


# Set Variables for later usage
buildlocation='/tmp/hab_effortless'
gitcommit=$( cat /tmp/gitcommit )
origin='aig'
authtoken=$( cat /tmp/authtoken )
bldrurl='http://plgsascs4324007.r1-core.r1.aig.net'
repourl="https://github.aig.net/aigchef/hab_effortless.git"
pkgversion=$( cat /tmp/pkgversion )

# Install Habitat on system
# curl -o /tmp/habinstall.sh https://raw.githubusercontent.com/habitat-sh/habitat/master/components/hab/install.sh
# habv2install='bash /tmp/habinstall.sh -v 1.5.50 -t x86_64-linux-kernel2'
# habinstall='bash /tmp/habinstall.sh -v 1.5.50'
# if [[ $(uname -r) =~ ^2 ]] ; then ${habv2install} ; else ${habinstall} ; fi

# Configure Habitat
export HAB_LICENSE="accept"
export HAB_ORIGIN="${origin}"
export HAB_AUTH_TOKEN="${authtoken}"
export HAB_FEAT_EVENT_STREAM="1"
export HAB_BLDR_URL="${bldrurl}"
export HAB_PKGVERSION="${pkgversion}"
# export RUST_LOG="debug"
# export RUST_BACKTRACE=1
hab license accept
hab origin key download aig 20190805204456
hab origin key download aig 20190805204456 -s
hab pkg install core/hab-studio -b
mkdir -p ~/.hab/etc
cat > ~/.hab/etc/cli.toml <<EOF
auth_token = "$authtoken"
origin = "$origin"
EOF

# Clone the Git repository if not running locally in Vagrant or if the repo path otherwise does not exist.
if [[ ! -d ${buildlocation} ]]
then
  mkdir $buildlocation
  hab pkg install core/git
  hab pkg exec core/git git clone ${repourl} ${buildlocation}
  fi

# Build the Habitat Package
cd ${buildlocation}
hab pkg exec core/git git checkout ${gitcommit}
sed -i "s/pkg_version.*/pkg_version=\'$pkgversion\'/g" habitat/plan.sh
hab studio -k $origin build .

# Validate that build succeeded
if [ -f $buildlocation/results/last_build.env ] ;
then
  echo 'Build was successful, proceeding.'
else
  echo 'Build was not successful.'
  exit 1
fi

# Publish package to on-prem Habitat Builder
## Gather build details for usage with variables
source $buildlocation/results/last_build.env

## Upload to Habitat Builder
hab pkg install $buildlocation/results/${pkg_artifact}
