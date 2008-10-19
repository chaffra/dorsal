#!/usr/bin/env bash

# This is Dorsal. Refer README and COPYING for more information about
# it as well as terms of distribution.

### Define helper functions ###

# Colours for progress and error reporting
BAD="\033[1;37;41m"
GOOD="\033[1;37;42m"
cecho() {
    COL=$1; shift
    echo -e "${COL}$@\033[0m"
}

quit_if_fail() {
    # Exit with some useful information if something goes wrong
    status=$?
    if [ $status -ne 0 ]
    then
	cecho $BAD 'Failure with exit status:' $status
	cecho $BAD 'Exit message:' $1
	exit $status
    fi
}

package_fetch (){
    # First make sure we're in the right directory before downloading
    cd ${DOWNLOAD_PATH}

    cecho $GOOD "Fetching ${NAME}"

    # Fetch the package appropriately from its source
    if [ ${PACKING} = ".tar.bz2" ] || [ ${PACKING} = ".tar.gz" ] || [ ${PACKING} = ".tbz2" ] || [ ${PACKING} = ".tgz" ]
    then
	# Only fetch tarballs that do not exist
	if [ ! -e ${NAME}${PACKING} ]
	then
	    wget -c ${SOURCE}${NAME}${PACKING}
	fi
    elif [ ${PACKING} = "hg" ]
    then
	# Suitably clone or update hg packages
	if [ ! -d ${NAME} ]
	then
	    hg clone ${SOURCE}${NAME}
	else
	    cd ${NAME}
	    hg pull --update ${SOURCE}${NAME}
	    cd ..
	fi
    fi
    
    # Quit with a useful message if someting goes wrong
    quit_if_fail "Error fetching ${NAME}."
}

package_unpack() {
    # First make sure we're in the right directory before unpacking
    cd ${DOWNLOAD_PATH}

    # Only need to unpack tarballs
    if [ ${PACKING} = ".tar.bz2" ] || [ ${PACKING} = ".tar.gz" ] ||  [ ${PACKING} = ".tbz2" ] || [ ${PACKING} = ".tgz" ]
    then
	cecho $GOOD "Unpacking ${NAME}"
	# Make sure the tarball was downloaded
	if [ ! -e ${NAME}${PACKING} ]
	then
	    cecho $BAD "${NAME}${PACKING} does not exist. Please download first."
	    exit 1
	fi
	# Set appropriate untar flag
	if [ ${PACKING} = ".tar.bz2" ] || [ ${PACKING} = ".tbz2" ]
	then
	    C="j"
	else
	    C="z"
	fi

	# Unpack the tarball only if it isn't already
	if [ ! -d "${NAME}" ]
	then
	    tar x${C}f ${NAME}${PACKING}
	fi
    fi

    # Quit with a useful message if someting goes wrong
    quit_if_fail "Error unpacking ${NAME}."
}

package_build() {
    # Get things ready for the compilation process
    cecho $GOOD "Building ${NAME}"
    if [ ! -d "${NAME}" ] && [ ! -d "${EXTRACTSTO}" ]
    then
        cecho $BAD "${NAME} does not exist -- please unpack first."
        exit 1
    fi

    # Move to the appropriate folder before compilation
    if [ -z "$EXTRACTSTO" ]
    then
	cd ${NAME}
    else
	cd ${EXTRACTSTO}
    fi

    # Use the appropriate build system to compile and install the
    # package
    if [ ${BUILDCHAIN} = "autotools" ]
    then
	if [ ! -e Makefile ] 
	then
	    ./configure ${CONFOPTS} --prefix=${INSTALL_PATH}
	fi
	make
	make install
    elif [ ${BUILDCHAIN} = "python" ]
    then
	python setup.py install --prefix=${INSTALL_PATH}
    elif [ ${BUILDCHAIN} = "custom" ]
    then
	# Add a check here to make sure it's properly defined
	package_specific_build
    fi

    # Quit with a useful message if someting goes wrong
    quit_if_fail "There was a problem building ${NAME}."
}

guess_platform() {
    # Try to guess the name of the platform we're running on.
    # Could do this by self-reporting (/etc/issue on linux), or by
    # checking for existence of specific directories or programs.
    if [ -f /etc/xthostname ]; then
	echo crayxt
    elif [ -f /etc/issue ]; then
	case "$(</etc/issue)" in
	    Debian*lenny/sid*)	echo sid;;
	    Ubuntu\ 7.10*)	echo gutsy;;
	    Ubuntu\ 8.04*)	echo hardy;;
	    Ubuntu\ 8.10*)	echo intrepid;;
	    CentOS*\ 4.4*)	echo centos4;;
	esac
    fi
}

### Start the build process ###

export ORIGDIR=`pwd`

# Read configuration variables from dorsal.cfg
source dorsal.cfg

# If any important variables are missing, revert them to defaults
if [ -z "$DOWNLOAD_PATH" ]
then
    DOWNLOAD_PATH=$HOME/downloads/src
fi

if [ -z "$INSTALL_PATH" ]
then
    INSTALL_PATH=$HOME/builds
fi

# Check if dorsal.sh was invoked correctly
if [ $# -ne 1 ]
then
    platform=platforms/`guess_platform`.platform
    if ! [ -e $platform ]
    then
	cecho $BAD "Error: Platform to build for not specified (and not autmatically recognized)."
	echo "Correct usage: ./dorsal.sh platforms/foo.platform"
	exit 1
    fi
    cecho $GOOD "Building with $platform:"
    # Show the initial comments of that file, as they often contain instructions about
    # packages that should be installed first etc. Remove first field '#' so that cut-
    # and-paste of e.g. apt-get commands is easy.
    awk '/^[^#]/ {exit} {$1=""; print}' <$platform
    cecho $GOOD "Ok? Press enter to continue build, or ctrl-c to quit."
    read
else
    platform=$1
fi

# Make sure the requested platform exists
if [ -e "$platform" ]
then
    source $platform
else
    cecho $BAD "Platform set '$platform' not found. Refer README to check if your platform is supported."
    exit 1
fi

# Create necessary directories and export appropriate variables
mkdir -p ${DOWNLOAD_PATH}
mkdir -p ${INSTALL_PATH}/bin
export PATH=$INSTALL_PATH/bin:$PATH
export LD_LIBRARY_PATH=$INSTALL_PATH/lib:$LD_LIBRARY_PATH
export PYTHONPATH=$INSTALL_PATH/lib/python2.6/site-packages:$PYTHONPATH
export PKG_CONFIG_PATH=$INSTALL_PATH/lib/pkgconfig:$PKG_CONFIG_PATH:/usr/lib/pkgconfig

# Fetch and build individual packages
for PACKAGE in ${PACKAGES[@]} 
do
    cd ${ORIGDIR}
    if [ ! -e packages/${PACKAGE}.package ]
    then
        cecho $BAD "packages/${PACKAGE}.package does not exist yet. Please create it."
        exit 1
    fi

    unset NAME
    unset SOURCE
    unset PACKING
    unset BUILDCHAIN
    unset CONFOPTS
    unset EXTRACTSTO
    unset -f package_specific_build
    
    source packages/${PACKAGE}.package

    if [ ! ${NAME} ] || [ ! ${SOURCE} ] || [ ! ${PACKING} ] || [ ! ${BUILDCHAIN} ]
    then
	cecho $BAD "${PACKAGE}.package is not properly formed. Please check that all necessary variables are defined."
	exit 1
    fi

    package_fetch
    package_unpack
    package_build
done
