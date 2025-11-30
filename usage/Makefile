# Labelle Pathfinding - Usage Examples Makefile
#
# Available targets:
#   make all          - Build and run all examples
#   make floyd        - Run Floyd-Warshall example
#   make astar        - Run A* algorithm example
#   make compare      - Run algorithm comparison example
#   make clean        - Clean build artifacts
#   make help         - Show this help message

.PHONY: all floyd astar compare clean help

# Default target
all: floyd astar compare

# Floyd-Warshall example
floyd:
	@cd .. && zig build run-floyd

# A* algorithm example
astar:
	@cd .. && zig build run-astar

# Comparison example
compare:
	@cd .. && zig build run-compare

# Clean build artifacts
clean:
	@cd .. && rm -rf zig-out .zig-cache
	@echo "Build artifacts cleaned."

# Help
help:
	@echo "Labelle Pathfinding - Usage Examples"
	@echo ""
	@echo "Available targets:"
	@echo "  make all      - Build and run all examples"
	@echo "  make floyd    - Run Floyd-Warshall example"
	@echo "  make astar    - Run A* algorithm example"
	@echo "  make compare  - Run algorithm comparison example"
	@echo "  make clean    - Clean build artifacts"
	@echo "  make help     - Show this help message"
	@echo ""
	@echo "You can also run examples from the project root:"
	@echo "  zig build run-floyd"
	@echo "  zig build run-astar"
	@echo "  zig build run-compare"
	@echo "  zig build run-examples  (runs all)"
