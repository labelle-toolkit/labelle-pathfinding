# Labelle Pathfinding - Makefile
#
# Available targets:
#   make test         - Run unit tests
#   make spec         - Run zspec tests
#   make floyd        - Run Floyd-Warshall example
#   make astar        - Run A* algorithm example
#   make compare      - Run algorithm comparison example
#   make examples     - Run all examples
#   make raylib       - Run raylib visualization example
#   make raylib-building - Run raylib building example
#   make clean        - Clean build artifacts
#   make help         - Show this help message

.PHONY: all test spec floyd astar compare examples raylib raylib-building clean help

# Default target
all: test spec

# Run unit tests
test:
	@zig build test

# Run zspec tests
spec:
	@zig build spec

# Floyd-Warshall example
floyd:
	@zig build run-floyd

# A* algorithm example
astar:
	@zig build run-astar

# Comparison example
compare:
	@zig build run-compare

# Run all examples
examples:
	@zig build run-examples

# Raylib visualization example
raylib:
	@zig build run-raylib

# Raylib building example
raylib-building:
	@zig build run-raylib-building

# Clean build artifacts
clean:
	@rm -rf zig-out .zig-cache
	@echo "Build artifacts cleaned."

# Help
help:
	@echo "Labelle Pathfinding"
	@echo ""
	@echo "Testing:"
	@echo "  make test      - Run unit tests"
	@echo "  make spec      - Run zspec tests"
	@echo "  make all       - Run all tests (default)"
	@echo ""
	@echo "Examples:"
	@echo "  make floyd     - Run Floyd-Warshall example"
	@echo "  make astar     - Run A* algorithm example"
	@echo "  make compare   - Run algorithm comparison example"
	@echo "  make examples  - Run all examples"
	@echo "  make raylib    - Run raylib visualization example"
	@echo "  make raylib-building - Run multi-floor building example"
	@echo ""
	@echo "Other:"
	@echo "  make clean     - Clean build artifacts"
	@echo "  make help      - Show this help message"
