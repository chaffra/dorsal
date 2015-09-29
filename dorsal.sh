#!/usr/bin/env bash
set -a

# This is Dorsal. Refer to the files README and COPYING.lesser for
# more information about it as well as terms of distribution.

# The Unix date command does not work with nanoseconds, so use
# the GNU date instead. This is available in the 'coreutils' package
# from MacPorts.
DATE_CMD=$(which gdate 2>/dev/null)
if [ $? != 0 ]; then
    DATE_CMD=$(which date)
fi

# Start global timer
TIC_GLOBAL="$(${DATE_CMD} +%s%N)"

# Colours for progress and error reporting
BAD="\033[1;31m"
GOOD="\033[1;32m"
BOLD="\033[1m"

### Define helper functions ###

prettify_dir() {
   # Make a directory name more readable by replacing homedir with "~"
   echo ${1/#$HOME\//~\/}
}

cecho() {
    # Display messages in a specified colour
    COL=$1; shift
    echo -e "${COL}$@\033[0m"
}

default () {
    # Export a variable, if it is not already set
    VAR="${1%%=*}"
    VALUE="${1#*=}"
    eval "[[ \$$VAR ]] || export $VAR='$VALUE'"
}

quit_if_fail() {
    # Exit with some useful information if something goes wrong
    STATUS=$?
    if [ ${STATUS} -ne 0 ]
    then
	cecho ${BAD} 'Failure with exit status:' ${STATUS}
	cecho ${BAD} 'Exit message:' $1
	exit ${STATUS}
    fi
}

package_fetch () {
    # First, make sure we're in the right directory before downloading
    cd ${DOWNLOAD_PATH}

    cecho ${GOOD} "Fetching ${NAME}"

    # Fetch the package appropriately from its source
    if [ ${PACKING} = ".tar.bz2" ] || [ ${PACKING} = ".tar.gz" ] || [ ${PACKING} = ".tbz2" ] || [ ${PACKING} = ".tgz" ] || [ ${PACKING} = ".tar.xz" ] || [ ${PACKING} = ".zip" ]
    then
      # Only download archives that do not exist
      if [ ! -e ${NAME}${PACKING} ]
      then
        if [ ${STABLE_BUILD} = false ] && [ ${USE_SNAPSHOTS} = true ]
        then
          wget --retry-connrefused --no-check-certificate --server-response -c ${SOURCE}${NAME}${PACKING}
        else
          wget --retry-connrefused --no-check-certificate -c ${SOURCE}${NAME}${PACKING}
        fi
      fi

      # Download again when using snapshots and unstable packages, but
      # only when the timestamp has changed
      if [ ${STABLE_BUILD} = false ] && [ ${USE_SNAPSHOTS} = true ]
      then
        wget --timestamping --retry-connrefused --no-check-certificate ${SOURCE}${NAME}${PACKING}
      fi
    elif [ ${PACKING} = "hg" ]
    then
      # Suitably clone or update hg repositories
      if [ ! -d ${NAME} ]
      then
        hg clone ${SOURCE}${NAME}
      else
        cd ${NAME}
        hg pull --update
        cd ..
      fi
    elif [ ${PACKING} = "svn" ]
    then
      # Suitably check out or update svn repositories
      if [ ! -d ${NAME} ]
      then
  	    svn co ${SOURCE} ${NAME}
      else
        cd ${NAME}
        svn up
        cd ..
      fi
    elif [ ${PACKING} = "git" ]
    then
      # Suitably clone or update git repositories
      if [ ! -d ${NAME} ]
      then
        git clone ${SOURCE}${NAME}
      else
        cd ${NAME}
        git pull
        cd ..
      fi
    elif [ ${PACKING} = "bzr" ]
    then
      # Suitably branch or update bzr repositories
      if [ ! -d ${NAME} ]
      then
        bzr branch ${SOURCE}${NAME}
      else
        cd ${NAME}
        bzr pull
        cd ..
      fi
    fi

    # Quit with a useful message if something goes wrong
    quit_if_fail "Error fetching ${NAME}."
}

package_verify() {
    # First make sure we're in the right directory before verifying checksum
    cd ${DOWNLOAD_PATH}

    # Only need to verify archives
    if [ ${PACKING} = ".tar.bz2" ] || [ ${PACKING} = ".tar.gz" ] ||  [ ${PACKING} = ".tbz2" ] || [ ${PACKING} = ".tgz" ] || [ ${PACKING} = ".tar.xz" ] || [ ${PACKING} = ".zip" ]
    then

      cecho ${GOOD} "Verifying ${NAME}"

      # Check checksum has been specified for the package
      if [ -z "${CHECKSUM}" ]
      then
        cecho ${BAD} "No checksum for ${NAME}${PACKING}"
        return 1
      fi

      # Skip checksum if asked to ignore
      if [ "${CHECKSUM}" = "ignore" ]
      then
        return 1
      fi

      # Make sure the archive was downloaded
      if [ ! -e ${NAME}${PACKING} ]
      then
        cecho ${BAD} "${NAME}${PACKING} does not exist. Please download first."
        exit 1
      fi

      # Verify checksum using md5/md5sum
      if builtin command -v md5 > /dev/null; then
	  test "${CHECKSUM}" = "$(md5 -q ${NAME}${PACKING})" && echo "${NAME}${PACKING}: OK"
      elif builtin command -v md5sum > /dev/null ; then
	  echo "${CHECKSUM}  ${NAME}${PACKING}" | md5sum --check -
      else
	  cecho ${BAD} "Neither md5 nor md5sum were found in the PATH"
	  return 1
      fi
    fi

    # Quit with a useful message if something goes wrong
    quit_if_fail "Error verifying checksum for ${NAME}${PACKING}"
}

package_unpack() {
    # First make sure we're in the right directory before unpacking
    cd ${DOWNLOAD_PATH}

    # Only need to unpack archives
    if [ ${PACKING} = ".tar.bz2" ] || [ ${PACKING} = ".tar.gz" ] ||  [ ${PACKING} = ".tbz2" ] || [ ${PACKING} = ".tgz" ] || [ ${PACKING} = ".tar.xz" ] || [ ${PACKING} = ".zip" ]
    then
      cecho ${GOOD} "Unpacking ${NAME}"
      # Make sure the archive was downloaded
      if [ ! -e ${NAME}${PACKING} ]
      then
        cecho ${BAD} "${NAME}${PACKING} does not exist. Please download first."
        exit 1
      fi

      # Unpack the archive only if it isn't already or when using
      # snapshots and unstable packages
      if [ ${STABLE_BUILD} = false ] && [ ${USE_SNAPSHOTS} = true ] || [ ! -d "${EXTRACTSTO}" ]
      then
        # Unpack the archive in accordance with its packing
        if [ ${PACKING} = ".tar.bz2" ] || [ ${PACKING} = ".tbz2" ]
        then
          tar xjf ${NAME}${PACKING}
        elif [ ${PACKING} = ".tar.gz" ] || [ ${PACKING} = ".tgz" ]
        then
          tar xzf ${NAME}${PACKING}
        elif [ ${PACKING} = ".tar.xz" ]
        then
          tar xJf ${NAME}${PACKING}
        elif [ ${PACKING} = ".zip" ]
        then
          unzip ${NAME}${PACKING}
	fi
      fi
    fi

    # Quit with a useful message if something goes wrong
    quit_if_fail "Error unpacking ${NAME}."
}

package_build() {
    # Get things ready for the compilation process
    cecho ${GOOD} "Building ${NAME}"
    if [ ! -d "${EXTRACTSTO}" ]
    then
        cecho ${BAD} "${EXTRACTSTO} does not exist -- please unpack first."
        exit 1
    fi

    BUILDDIR=${EXTRACTSTO}
    SRCDIR=.

    # Create build directory if it does not exist
    if [ ! -d ${BUILDDIR} ]
    then
        mkdir -p ${BUILDDIR}
    fi

    # Move to the build directory
    cd ${BUILDDIR}

    # Carry out any package-specific setup
    package_specific_setup
    quit_if_fail "There was a problem in build setup for ${NAME}."

    # Use the appropriate build system to compile and install the
    # package
    for cmd_file in dorsal_configure dorsal_build; do
	echo "#!/usr/bin/env bash" >${cmd_file}
	chmod a+x ${cmd_file}

    # Write variables to files so that they can be run stand-alone
	declare -x >>${cmd_file}
	sed -i'' s/"CommonProgramFiles(x86)"/"CommonProgramFiles_x86"/g ${cmd_file}
	sed -i'' s/"ProgramFiles(x86)"/"ProgramFiles_x86"/g ${cmd_file}

        # From this point in dorsal_*, errors are fatal
	echo "set -e" >>${cmd_file}
    done

    if [ ${BUILDCHAIN} = "autotools" ]
    then
        if [ -f ${SRCDIR}/configure ]
        then
	    echo ${SRCDIR}/configure ${CONFOPTS} --prefix=${INSTALL_PATH} >>dorsal_configure
        fi
        for target in "${TARGETS[@]}"
        do
            echo ${MAKE} ${MAKEOPTS} -j ${PROCS} $target >>dorsal_build
        done
    elif [ ${BUILDCHAIN} = "python" ]
    then
        echo ${PYTHON_EXECUTABLE} setup.py install --prefix=${INSTALL_PATH} >>dorsal_build
    elif [ ${BUILDCHAIN} = "scons" ]
    then
        for target in "${TARGETS[@]}"
        do
            echo scons -j ${PROCS} ${SCONSOPTS} prefix=${INSTALL_PATH} $target >>dorsal_build
        done
    elif [ ${BUILDCHAIN} = "cmake" ]
    then
        BUILD_DIR="./dorsal_build_dir"
        echo mkdir -p ${BUILD_DIR} >>dorsal_configure
        echo cd ${BUILD_DIR} >>dorsal_configure
        echo rm -f CMakeCache.txt >>dorsal_configure
		if [ "$MSYSTEM" == "MSYS" ];
		then
			echo cmake -G"MSYS\ Makefiles" ${CONFOPTS} -D CMAKE_INSTALL_PREFIX:PATH=${INSTALL_PATH} ../ >>dorsal_configure
		elif [ "$MSYSTEM" = "MINGW64" ]
		then
		    echo cmake -G"MSYS\ Makefiles" ${CONFOPTS} -D CMAKE_INSTALL_PREFIX:PATH=${INSTALL_PATH} ../ >>dorsal_configure
		else
		    echo cmake ${CONFOPTS} -D CMAKE_INSTALL_PREFIX:PATH=${INSTALL_PATH} ../ >>dorsal_configure
		fi
        for target in "${TARGETS[@]}"
        do
            echo ${MAKE} -C ${BUILD_DIR} ${MAKEOPTS} -j ${PROCS} $target >>dorsal_build
        done
    elif [ ${BUILDCHAIN} = "custom" ]
    then
        # Write the function definition to file
        declare -f package_specific_build >>dorsal_build
        echo package_specific_build >>dorsal_build
    fi
    echo "touch dorsal_successful_build" >> dorsal_build

    # Run the generated build scripts
    if [ ${BASH_VERSINFO} -ge 3 ]
    then
	set -o pipefail
	./dorsal_configure 2>&1 | tee dorsal_configure.log
    else
	./dorsal_configure
    fi
    quit_if_fail "There was a problem configuring ${NAME}."

    if [ ${BASH_VERSINFO} -ge 3 ]
    then
	set -o pipefail
	./dorsal_build 2>&1 | tee dorsal_build.log
    else
	./dorsal_build
    fi
    quit_if_fail "There was a problem building ${NAME}."

    # Carry out any package-specific post-build instructions
    package_specific_install
    quit_if_fail "There was a problem in post-build instructions for ${NAME}."
}

package_register() {
    # Get ready to set environment variables related to the package
    cd ${DOWNLOAD_PATH}
    if [ ! -d "${EXTRACTSTO}" ]
    then
        cecho ${BAD} "${EXTRACTSTO} does not exist -- please install at least once."
        exit 1
    fi

    # Move to the package directory
    cd ${EXTRACTSTO}

    # Set any package-specific environment variables
    package_specific_register
    quit_if_fail "There was a problem setting environment variables for ${NAME}."
}

guess_platform() {
  # Try to guess the name of the platform we're running on
  if [ -f /usr/bin/cygwin1.dll ]
  then
      echo xp
  elif [ -f /etc/fedora-release ]
  then
      local FEDORANAME=`gawk '{if (match($0,/\((.*)\)/,f)) print f[1]}' /etc/fedora-release`
      case ${FEDORANAME} in
          Cambridge*)   echo fedora10;;
          Leonidas*)    echo fedora11;;
          Constantine*) echo fedora12;;
          Goddard*)     echo fedora13;;
          Laughlin*)    echo fedora14;;
          Lovelock*)    echo fedora15;;
      esac
  elif [ -x /usr/bin/sw_vers ]
  then
    local MACOSVER=$(sw_vers -productVersion)
    case ${MACOSVER} in
      10.4*) 	echo tiger;;
      10.5*)	echo leopard;;
      10.6*)	echo snowleopard;;
      10.7*)    echo lion;;
      10.8*)    echo mountainlion;;
    esac
  elif [ -x /usr/bin/lsb_release ]; then
    local DISTRO=$(lsb_release -i -s)
    local CODENAME=$(lsb_release -c -s)
    local DESCRIPTION=$(lsb_release -d -s)
    case ${DISTRO}:${CODENAME}:${DESCRIPTION} in
      Ubuntu:*:*)            echo ${CODENAME};;
      Debian:*:*)            echo ${CODENAME};;
      Gentoo:*:*)            echo gentoo;;
      *:Nahant*:*)           echo rhel4;;
      *:Tikanga*:*)          echo rhel5;;
      Scientific:Carbon*:*)  echo rhel6;;
      *:*:*CentOS*\ 4*)      echo rhel4;;
      *:*:*CentOS*\ 5*)      echo rhel5;;
      *:*:*openSUSE\ 11.1*)  echo opensuse11.1;;
      *:*:*openSUSE\ 11.2*)  echo opensuse11.2;;
      *:*:*openSUSE\ 11.3*)  echo opensuse11.3;;
      *:*:*openSUSE\ 11.4*)  echo opensuse11.4;;
      *:*:*openSUSE\ 12.1*)  echo opensuse12.1;;
    esac
  fi
}

guess_architecture() {
  # Try to guess the architecture of the platform we are running on
    ARCH=unknown
    if [ -x /usr/bin/uname -o -x /bin/uname ]
    then
	ARCH=`uname -m`
    fi
}

generate_fenics_conf() {
    # Generate configuration file for building against FEniCS installation

    mkdir -p $INSTALL_PATH/share/fenics
    CONFIG_FILE=$INSTALL_PATH/share/fenics/fenics.conf
    rm -f $CONFIG_FILE
    echo "
# Source this file to set up your environment for building against FEniCS

# Standard paths
export INSTALL_PATH=${INSTALL_PATH}
export PATH=\$INSTALL_PATH/bin:\$PATH
export PYTHONPATH=\$INSTALL_PATH/lib/python${PYTHONVER}/site-packages:\$PYTHONPATH
export LD_LIBRARY_PATH=\$INSTALL_PATH/lib:\$LD_LIBRARY_PATH
export DYLD_LIBRARY_PATH=\$INSTALL_PATH/lib:\$DYLD_LIBRARY_PATH
export PKG_CONFIG_PATH=\$INSTALL_PATH/lib/pkgconfig:\$PKG_CONFIG_PATH
export MANPATH=\$INSTALL_PATH/share/man:\$MANPATH
export CPLUS_INCLUDE_PATH=\$INSTALL_PATH/include:\$CPLUS_INCLUDE_PATH
export CMAKE_PREFIX_PATH=\$INSTALL_PATH:\$CMAKE_PREFIX_PATH
" >> $CONFIG_FILE

    # Add some extra library paths for 64 bit machines
    guess_architecture
    if [ "$ARCH" == "x86_64" ]; then
        echo "
# 64 bit paths
export PYTHONPATH=\$INSTALL_PATH/lib64/python${PYTHONVER}/site-packages:\$PYTHONPATH
export LD_LIBRARY_PATH=\$INSTALL_PATH/lib64:\$LD_LIBRARY_PATH
export DYLD_LIBRARY_PATH=\$INSTALL_PATH/lib64:\$DYLD_LIBRARY_PATH
" >> $CONFIG_FILE
    fi

    for PACKAGE in ${PACKAGES[@]}
    do
	case ${PACKAGE} in
            *boost) echo "
export BOOST_DIR=\$INSTALL_PATH
" >> $CONFIG_FILE;;
	    *vtk | *vtkwithqt) echo "
# FIXME: This needs to be updated when the VTK version is changed
export LD_LIBRARY_PATH=\$INSTALL_PATH/lib/vtk-5.8:\$LD_LIBRARY_PATH
export DYLD_LIBRARY_PATH=\$INSTALL_PATH/lib/vtk-5.8:\$DYLD_LIBRARY_PATH
" >> $CONFIG_FILE;;
	esac
    done

    echo
    echo "FEniCS has now been installed in"
    echo
    cecho ${GOOD} "    ${INSTALL_PATH}"
    echo
    echo "To update your environment variables, run the following command:"
    echo
    cecho ${GOOD} "    source $CONFIG_FILE"
    echo
    echo "For future reference, we recommend that you add this command to your"
    echo "configuration (.bashrc, .profile or similar)."
    echo

}

### Start the build process ###

export ORIG_DIR=`pwd`

# Read configuration variables from dorsal.cfg
source dorsal.cfg

# For changes specific to your local setup or for debugging, use local.cfg
if [ -f local.cfg ]
then
    source local.cfg
fi

# If any variables are missing, revert them to defaults
default PROJECT=FEniCS
default DOWNLOAD_PATH=${HOME}/Work/${PROJECT}/src
default INSTALL_PATH=${HOME}/Work/${PROJECT}
default PROCS=1
default STABLE_BUILD=true
default USE_SNAPSHOTS=false
default MAKE=make

# Check if project was specified correctly
if [ -d ${PROJECT} ]
then
  if [ -d ${PROJECT}/platforms -a -d ${PROJECT}/packages ]
  then
    cecho ${GOOD} "Found configuration for project ${PROJECT}."
  else
    cecho ${BAD} "No subdirectories 'platforms' and 'packages' in ${PROJECT}."
    echo "Please make sure there exists proper project configuration directory."
    exit 1
  fi
else
  cecho ${BAD} "Error: No project configuration directory found for project ${PROJECT}."
  echo "Please check if you have specified right project name in dorsal.cfg"
  echo "Please check if you have directory called ${PROJECT}"
  echo "with subdirectories ${PROJECT}/platforms and ${PROJECT}/packages"
  exit 1
fi

# Check if dorsal.sh was invoked correctly
if [ $# -eq 0 ]
then
    PLATFORM_SUPPORTED=${PROJECT}/platforms/supported/`guess_platform`.platform
    PLATFORM_CONTRIBUTED=${PROJECT}/platforms/contributed/`guess_platform`.platform
    PLATFORM_DEPRECATED=${PROJECT}/platforms/deprecated/`guess_platform`.platform
    if [ -e local.platform ]; then
        PLATFORM=local.platform
        cecho ${GOOD} "Building ${PROJECT} using local.platform"
    elif [ -e ${PLATFORM_SUPPORTED} ]; then
        PLATFORM=${PLATFORM_SUPPORTED}
        cecho ${GOOD} "Building ${PROJECT} using ${PLATFORM}."
    elif [ -e ${PLATFORM_CONTRIBUTED} ]; then
        PLATFORM=${PLATFORM_CONTRIBUTED}
        cecho ${GOOD} "Building ${PROJECT} using ${PLATFORM}."
        cecho ${BOLD} "Warning: Platform is not officially supported but may still work!"
    elif [ -e ${PLATFORM_DEPRECATED} ]; then
        PLATFORM=${PLATFORM_DEPRECATED}
        cecho ${GOOD} "Building ${PROJECT} using ${PLATFORM}."
        cecho ${BAD} "Warning: Platform is deprecated and will be removed shortly but may still work!"
    else
	cecho ${BAD} "Error: Platform to build for not specified (and not automatically recognised)."
	echo "If you know the platform you are interested in (myplatform), please specify it directly, as:"
	echo "./dorsal.sh ${PROJECT}/platforms/myplatform.platform"
	echo "If you'd like to learn more, refer to the file USAGE for detailed usage instructions."
	exit 1
    fi
    echo "-------------------------------------------------------------------------------"
    # Show the initial comments in the platform file, as it often
    # contains instructions about packages that should be installed
    # first, etc. Remove first field '#' so that cut-and-paste of
    # e.g. apt-get commands is easy.
    awk '/^##/ {exit} {$1=""; print}' <${PLATFORM}
    echo
    echo "Downloading files to:   $(prettify_dir "${DOWNLOAD_PATH}")"
    echo "Installing projects in: $(prettify_dir "${INSTALL_PATH}")"
    echo
    if [ ${STABLE_BUILD} = true ]
    then
      echo "Building stable point-releases of ${PROJECT} projects."
    else
	if [ ${USE_SNAPSHOTS} = true ]
	then
	    echo "Building development versions of ${PROJECT} projects (using snapshots)."
	else
	    echo "Building development versions of ${PROJECT} projects."
	fi
    fi
    echo "-------------------------------------------------------------------------------"
    cecho ${GOOD} "Please make sure you've read the instructions above and your system"
    cecho ${GOOD} "is ready for installing ${PROJECT}. We find it easiest to copy and paste"
    cecho ${GOOD} "these instructions in another terminal window."
    echo ""
    cecho ${GOOD} "Once ready, hit enter to continue!"
    read
elif [ $# -eq 1 ]
then
    PLATFORM=${1}
elif [ $# -eq 2 ]
then
    # Check if the user wants to install a single package
    if [ ${1} == "install-package" ]
    then
	PACKAGE=${2}
        # Check if the package exists
	if [ ! -e ${PROJECT}/packages/${PACKAGE}.package ]
	then
	    cecho ${BAD} "${PROJECT}/packages/${PACKAGE}.package does not exist yet. Please create it."
	    exit 1
	fi
	PACKAGES=(${PACKAGE})
	PLATFORM="${PROJECT}/platforms/.single"
    else
      echo "If you'd like to install a single package, please use the syntax:"
      echo "./dorsal.sh install-package foo"
	exit 1
    fi
fi

# Make sure the requested platform exists
if [ -e "${PLATFORM}" ]
then
    source ${PLATFORM}
else
    cecho ${BAD} "Platform set '${PLATFORM}' not found. Refer to the file README to check if your platform is supported."
    exit 1
fi


# If the PYTHON_EXECUTABLE environment variable hasn't been set,
# set it to the default python executable
default PYTHON_EXECUTABLE=$(which python)

# If the platform doesn't override the system python by installing its
# own, figure out the version of of the existing python
default PYTHONVER=`${PYTHON_EXECUTABLE} -c "import sys; print sys.version[:3]"`

# Create necessary directories and set appropriate variables
mkdir -p ${DOWNLOAD_PATH}
mkdir -p ${INSTALL_PATH}/bin
mkdir -p ${INSTALL_PATH}/conf
mkdir -p ${INSTALL_PATH}/include
mkdir -p ${INSTALL_PATH}/lib
mkdir -p ${INSTALL_PATH}/lib/python${PYTHONVER}/site-packages
mkdir -p ${INSTALL_PATH}/share
export PATH=${INSTALL_PATH}/bin:${PATH}
export LD_LIBRARY_PATH=${INSTALL_PATH}/lib:${LD_LIBRARY_PATH}
export DYLD_LIBRARY_PATH=${INSTALL_PATH}/lib:${DYLD_LIBRARY_PATH}

default PYTHONPATHSEP=`${PYTHON_EXECUTABLE} -c "import os; print os.pathsep"`
#export PYTHONPATH="${INSTALL_PATH}/lib${PYTHONPATHSEP}${PYTHONPATH}"
export PYTHONPATH="${INSTALL_PATH}/lib/python${PYTHONVER}/site-packages${PYTHONPATHSEP}${PYTHONPATH}"
export PKG_CONFIG_PATH=${INSTALL_PATH}/lib/pkgconfig:${PKG_CONFIG_PATH}
ORIG_PROCS=${PROCS}

# Add some extra library paths for 64 bit machines
guess_architecture
if [ "$ARCH" == "x86_64" ]; then
    export LD_LIBRARY_PATH=${INSTALL_PATH}/lib64:${LD_LIBRARY_PATH}
    export DYLD_LIBRARY_PATH=${INSTALL_PATH}/lib64:${DYLD_LIBRARY_PATH}
    export PYTHONPATH="${INSTALL_PATH}/lib64/python${PYTHONVER}/site-packages${PYTHONPATHSEP}${PYTHONPATH}"
fi

# Reset timings
TIMINGS=""

# Fetch and build individual packages
for PACKAGE in ${PACKAGES[@]}
do
    # Start timer
    TIC="$(${DATE_CMD} +%s%N)"

    # Return to the main Dorsal directory
    cd "${ORIG_DIR}"

    # Skip building this package if the user requests it
    SKIP=false
    case ${PACKAGE} in
	skip:*) SKIP=true;  PACKAGE=${PACKAGE#*:};;
	once:*) SKIP=maybe; PACKAGE=${PACKAGE#*:};;
    esac

    # Check if the package exists
    if [ ! -e ${PROJECT}/packages/${PACKAGE}.package ]
    then
        cecho ${BAD} "${PROJECT}/packages/${PACKAGE}.package does not exist yet. Please create it."
        exit 1
    fi

    # Reset package-specific variables
    unset NAME
    unset SOURCE
    unset PACKING
    unset CHECKSUM
    unset BUILDCHAIN
    unset CONFOPTS
    unset MAKEOPTS
    unset SCONSOPTS
    unset EXTRACTSTO
    TARGETS=('' install)
    PROCS=${ORIG_PROCS}

    # Reset package-specific functions
    package_specific_setup () { true; }
    package_specific_build () { true; }
    package_specific_install () { true; }
    package_specific_register () { true; }

    # Fetch information pertinent to the package
    source ${PROJECT}/packages/${PACKAGE}.package

    # Turn to a stable version of the package if that's what the user
    # wants and it exists
    if [ ${STABLE_BUILD} = true ] && [ -e ${PROJECT}/packages/${PACKAGE}-stable.package ]
    then
      source ${PROJECT}/packages/${PACKAGE}-stable.package
    elif [ ${STABLE_BUILD} = false ] && [ ${USE_SNAPSHOTS} = true ] && [ -e ${PROJECT}/packages/${PACKAGE}-snapshot.package ]
    then
      source ${PROJECT}/packages/${PACKAGE}-snapshot.package
    fi

    # Ensure that the package file is sanely constructed
    if [ ! "${NAME}" ] || [ ! "${SOURCE}" ] || [ ! "${PACKING}" ] || [ ! "${BUILDCHAIN}" ]
    then
        cecho ${BAD} "${PACKAGE}.package is not properly formed. Please check that all necessary variables are defined."
        exit 1
    fi

    # Most packages extract to a directory named after the package
    default EXTRACTSTO=${NAME}

    if [ ${SKIP} = maybe ] && [ ! -f ${DOWNLOAD_PATH}/${EXTRACTSTO}/dorsal_successful_build ]
    then
	SKIP=false
    fi

    # Fetch, unpack and build package
    if [ ${SKIP} = false ]
    then
      # Fetch, unpack and build the current package
      package_fetch
      package_verify
      package_unpack
      package_build
    else
      # Let the user know we're skipping the current package
      cecho ${GOOD} "Skipping ${NAME}"
    fi
    package_register

    # Store timing
    TOC="$(($(${DATE_CMD} +%s%N)-TIC))"
    TIMINGS="$TIMINGS"$"\n""$PACKAGE: ""$((TOC/1000000000)) s"

done

# Stop global timer
TOC_GLOBAL="$(($(${DATE_CMD} +%s%N)-TIC_GLOBAL))"

# Display a summary
echo
cecho ${GOOD} "Build finished in $((TOC_GLOBAL/1000000000)) seconds."
echo
echo "Summary of timings:"
echo -e "$TIMINGS"

# Generate FEniCS config file if we're building FEniCS
if [ ${PROJECT} = "FEniCS" ]; then
    generate_fenics_conf
fi
