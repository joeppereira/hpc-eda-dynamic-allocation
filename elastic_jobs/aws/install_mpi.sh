#!/bin/bash
# Install PMIx-enabled OpenMPI for elastic jobs

set -e

echo "=========================================="
echo "Install PMIx-Enabled OpenMPI"
echo "=========================================="
echo ""

OPENMPI_VERSION="4.1.6"
INSTALL_PREFIX="/opt/openmpi"
BUILD_DIR="/tmp/openmpi-build"

echo "Configuration:"
echo "  Version: $OPENMPI_VERSION"
echo "  Install prefix: $INSTALL_PREFIX"
echo ""

# Check if already installed
if [ -f "$INSTALL_PREFIX/bin/mpirun" ]; then
    echo "OpenMPI already installed at $INSTALL_PREFIX"
    $INSTALL_PREFIX/bin/mpirun --version
    echo ""
    read -p "Reinstall? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping installation"
        exit 0
    fi
fi

echo "Step 1: Install build dependencies"
sudo yum groupinstall -y "Development Tools"
sudo yum install -y \
    wget \
    gcc \
    gcc-c++ \
    make \
    perl \
    libevent-devel \
    hwloc-devel \
    pmix-devel \
    slurm-devel

echo "✓ Dependencies installed"
echo ""

echo "Step 2: Download OpenMPI $OPENMPI_VERSION"
mkdir -p $BUILD_DIR
cd $BUILD_DIR

if [ ! -f "openmpi-${OPENMPI_VERSION}.tar.gz" ]; then
    wget https://download.open-mpi.org/release/open-mpi/v4.1/openmpi-${OPENMPI_VERSION}.tar.gz
fi

echo "✓ Downloaded"
echo ""

echo "Step 3: Extract source"
tar xzf openmpi-${OPENMPI_VERSION}.tar.gz
cd openmpi-${OPENMPI_VERSION}
echo "✓ Extracted"
echo ""

echo "Step 4: Configure (this may take a few minutes)"
./configure \
    --prefix=$INSTALL_PREFIX \
    --with-pmix \
    --with-slurm \
    --with-libevent \
    --with-hwloc \
    --enable-mpi-cxx \
    --enable-mpi-fortran=no \
    2>&1 | tee configure.log

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "✗ Configuration failed"
    echo "Check configure.log for details"
    exit 1
fi

echo "✓ Configured"
echo ""

echo "Step 5: Build (this will take 10-20 minutes)"
make -j$(nproc) 2>&1 | tee build.log

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "✗ Build failed"
    echo "Check build.log for details"
    exit 1
fi

echo "✓ Built"
echo ""

echo "Step 6: Install"
sudo make install 2>&1 | tee install.log

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "✗ Installation failed"
    echo "Check install.log for details"
    exit 1
fi

echo "✓ Installed"
echo ""

echo "Step 7: Create module file"
sudo mkdir -p /opt/modulefiles/openmpi

sudo tee /opt/modulefiles/openmpi/${OPENMPI_VERSION} > /dev/null <<EOF
#%Module1.0
##
## OpenMPI ${OPENMPI_VERSION} with PMIx support
##
proc ModulesHelp { } {
    puts stderr "OpenMPI ${OPENMPI_VERSION} with PMIx and SLURM support"
}

module-whatis "OpenMPI ${OPENMPI_VERSION} with PMIx"

set basedir ${INSTALL_PREFIX}

prepend-path PATH \$basedir/bin
prepend-path LD_LIBRARY_PATH \$basedir/lib
prepend-path MANPATH \$basedir/share/man
prepend-path PKG_CONFIG_PATH \$basedir/lib/pkgconfig

setenv MPI_HOME \$basedir
setenv OMPI_MCA_btl_base_warn_component_unused 0
EOF

echo "✓ Module file created"
echo ""

echo "Step 8: Verify installation"
$INSTALL_PREFIX/bin/mpirun --version
echo ""

echo "Check PMIx support:"
$INSTALL_PREFIX/bin/ompi_info | grep -i pmix
echo ""

echo "Step 9: Test MPI"
cat > /tmp/mpi_test.c <<'EOF'
#include <mpi.h>
#include <stdio.h>

int main(int argc, char** argv) {
    MPI_Init(&argc, &argv);
    
    int world_size, world_rank;
    MPI_Comm_size(MPI_COMM_WORLD, &world_size);
    MPI_Comm_rank(MPI_COMM_WORLD, &world_rank);
    
    char processor_name[MPI_MAX_PROCESSOR_NAME];
    int name_len;
    MPI_Get_processor_name(processor_name, &name_len);
    
    printf("Hello from rank %d/%d on %s\n", 
           world_rank, world_size, processor_name);
    
    MPI_Finalize();
    return 0;
}
EOF

$INSTALL_PREFIX/bin/mpicc /tmp/mpi_test.c -o /tmp/mpi_test
$INSTALL_PREFIX/bin/mpirun -n 4 /tmp/mpi_test

echo ""
echo "✓ MPI test passed"
echo ""

echo "Step 10: Cleanup"
cd /
rm -rf $BUILD_DIR
echo "✓ Build directory cleaned"
echo ""

echo "=========================================="
echo "✓ OpenMPI Installation Complete"
echo "=========================================="
echo ""
echo "Installation location: $INSTALL_PREFIX"
echo ""
echo "To use OpenMPI:"
echo "  module load openmpi/${OPENMPI_VERSION}"
echo "  mpirun --version"
echo ""
echo "Or add to your PATH:"
echo "  export PATH=$INSTALL_PREFIX/bin:\$PATH"
echo "  export LD_LIBRARY_PATH=$INSTALL_PREFIX/lib:\$LD_LIBRARY_PATH"
echo ""
echo "Next steps:"
echo "  1. Test elastic jobs: ./test_elastic.sh"
echo "  2. Submit elastic job: python3 ../scripts/submit_elastic.py"
echo ""
