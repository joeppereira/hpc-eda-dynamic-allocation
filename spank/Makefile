# Makefile for SPANK monitor plugin

CC = gcc
CFLAGS = -Wall -fPIC -shared
LDFLAGS = -lslurm -lpthread

# SLURM installation paths (adjust if needed)
SLURM_INCLUDE = /usr/include
SLURM_LIB = /usr/lib64

# Plugin name
PLUGIN = spank_monitor.so

# Source files
SRC = spank_monitor.c

all: $(PLUGIN)

$(PLUGIN): $(SRC)
	$(CC) $(CFLAGS) -I$(SLURM_INCLUDE) -L$(SLURM_LIB) $(LDFLAGS) -o $@ $<

clean:
	rm -f $(PLUGIN)

install: $(PLUGIN)
	@echo "Installing SPANK plugin..."
	sudo mkdir -p /opt/slurm/lib/slurm
	sudo cp $(PLUGIN) /opt/slurm/lib/slurm/
	@echo "Plugin installed to /opt/slurm/lib/slurm/$(PLUGIN)"
	@echo ""
	@echo "Next steps:"
	@echo "1. Add to /etc/slurm/plugstack.conf:"
	@echo "   required /opt/slurm/lib/slurm/$(PLUGIN)"
	@echo "2. Restart SLURM:"
	@echo "   sudo systemctl restart slurmctld slurmd"

test:
	@echo "Testing SPANK plugin..."
	@if [ -f /opt/slurm/lib/slurm/$(PLUGIN) ]; then \
		echo "✓ Plugin installed"; \
	else \
		echo "✗ Plugin not installed"; \
	fi
	@if grep -q "spank_monitor" /etc/slurm/plugstack.conf 2>/dev/null; then \
		echo "✓ Plugin configured in plugstack.conf"; \
	else \
		echo "✗ Plugin not configured"; \
	fi

.PHONY: all clean install test
