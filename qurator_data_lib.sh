# ______________________________________
#/ always copy the file from            \
#| mono-repo/qurator_data_lib.sh, never |
#\ edit the copy in the project         /
# --------------------------------------
#        \   ^__^
#         \  (oo)\_______
#            (__)\       )\/\
#                ||----w |
#                ||     ||

if [ -z "$BASH" ]; then
  echo "qurator_data_lib.sh uses bash features, please make sure to run $0 in bash"
  exit 1
fi

check_data_subdir() {
  result=0

  if git submodule status $DATA_SUBDIR | grep -q '^-'; then
    echo "$DATA_SUBDIR/ is not an initialized submodule"; result=1
  fi
  if ! [ -e $DATA_SUBDIR/.git/annex ]; then
    echo "$DATA_SUBDIR/ is not a git annex repository"; result=1
  fi
  if ! (cd $DATA_SUBDIR && git annex version | egrep -q 'local repository version: (7|8)'); then
    echo "$DATA_SUBDIR/ is not a git annex repository version 7 or 8"; result=1
  fi
  if ! (cd $DATA_SUBDIR && git remote | grep -q '^nfs$'); then
    echo "$DATA_SUBDIR/ has no git remote 'nfs'"; result=1
  fi

  return $result
}

annex_get() {
  if [[ "$1" = '--allow_symlinks' ]]; then
    allow_symlinks=1
    shift
  else
    allow_symlinks=0
  fi
  file_pattern="$1"

  (
    cd $DATA_SUBDIR
    git annex get $file_pattern

    # fsck seems to be necessary to fix the files if we are in a submodule
    git annex fsck $file_pattern

    # Check that there are no symlinks = only unlocked files. This is needed for
    # Docker builds, as we cannot dereference symlinks in a Dockerfile COPY.
    if [[ $allow_symlinks = 0 ]]; then
      git ls-files $file_pattern | while read f; do
        if ! [[ -f "$f" ]]; then
           echo "$DATA_SUBDIR/$f is not a regular file – Is an unlock needed?"
           exit
        fi
      done
    fi
  )
}

# Options:
# --no-unpack                Do NOT unpack the file
# --strip-components NUMBER  (as tar's option)
download_to() {
  unpack=1
  tar_options=""

  _options=$(getopt --long no-unpack,strip-components: -- "" "$@")
  if [[ $? != 0 ]]; then
    echo "Bad parameters for download_to" >&2
    exit 1
  fi
  eval set -- "$_options"
  while true; do
    case "$1" in
    --no-unpack)
      unpack=0
      ;;
    --strip-components)
      shift
      components=$1
      tar_options="$tar_options --strip-components $components"
      ;;
    --)
      shift
      break
      ;;
    esac
    shift
  done

  download_source="$1"
  dest="$2"

  (
    cd $DATA_SUBDIR
    tmpf=`mktemp 'tmp.XXXXX'`
    curl -sSL -o $tmpf "$download_source"
    if [[ $unpack = 1 ]]; then
      mkdir -p "$dest"
      # Unpacking relies on tar -a unpacking any tar compression
      tar -C "$dest" $tar_options -af $tmpf -xv
      rm -f $tmpf
    else
      dest_dir=`dirname "$dest"`
      mkdir -p "$dest_dir"
      mv $tmpf "$dest"
    fi
  )
}

suggest_commands() {
  echo "Suggested commands:"
  echo
  echo "git submodule update --init"
  echo "(cd $DATA_SUBDIR && git annex init --version=7)"
  echo "(cd $DATA_SUBDIR && git remote add nfs annex@b-lx0053.sbb.spk-berlin.de:/var/lib/annex/qurator-data.git)"
}

handle_data() {
  if [[ "$1" = '--no-download' ]]; then
    no_download=1
    shift
  else
    no_download=0
  fi

  if [ -n "$FORCE_DOWNLOAD" ]; then
    get_from_web
  elif ! check_data_subdir; then
    if [[ $no_download = 1 ]]; then
      select choice in "Abort to manually fix $DATA_SUBDIR submodule"; do
        if [ $REPLY = 1 ]; then
          suggest_commands
          exit
        fi
      done
    else
      select choice in "Abort to manually fix $DATA_SUBDIR submodule" "Download data files from the web"; do
        if [ $REPLY = 1 ]; then
          suggest_commands
          exit
        else
          get_from_web
          break
        fi
      done
    fi
  else
    get_from_annex
  fi
}
