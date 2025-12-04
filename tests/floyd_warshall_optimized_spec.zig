const std = @import("std");
const zspec = @import("zspec");
const pathfinding = @import("pathfinding");

const expect = zspec.expect;

/// Test the SIMD-only optimized implementation
pub const FloydWarshallOptimizedSpec = struct {
    var fw: pathfinding.FloydWarshallSimd = undefined;

    test "tests:before" {
        fw = pathfinding.FloydWarshallSimd.init(std.testing.allocator);
    }

    test "tests:after" {
        fw.deinit();
    }

    pub const @"initialization" = struct {
        test "creates with zero size" {
            try expect.equal(fw.last_key, 0);
            try expect.equal(fw.size, 0);
        }
    };

    pub const @"simple linear graph" = struct {
        test "tests:before" {
            fw.resize(3);
            try fw.clean();
            // Create graph: 0 -> 1 -> 2
            fw.addEdge(0, 1, 1);
            fw.addEdge(1, 2, 1);
            fw.generate();
        }

        test "finds path between connected nodes" {
            try expect.toBeTrue(fw.hasPath(0, 1));
            try expect.toBeTrue(fw.hasPath(1, 2));
            try expect.toBeTrue(fw.hasPath(0, 2));
        }

        test "calculates correct distances" {
            try expect.equal(fw.value(0, 1), 1);
            try expect.equal(fw.value(1, 2), 1);
            try expect.equal(fw.value(0, 2), 2);
        }

        test "returns INF for unreachable nodes" {
            try expect.toBeFalse(fw.hasPath(2, 0));
        }

        test "returns zero for self-loops" {
            try expect.equal(fw.value(0, 0), 0);
            try expect.equal(fw.value(1, 1), 0);
        }
    };

    pub const @"entity ID mapping" = struct {
        test "tests:before" {
            fw.resize(4);
            try fw.clean();
            // Use entity IDs: 100 -> 200 -> 300 -> 400
            fw.addEdgeWithMapping(100, 200, 1);
            fw.addEdgeWithMapping(200, 300, 1);
            fw.addEdgeWithMapping(300, 400, 1);
            fw.generate();
        }

        test "maps entity IDs to internal indices" {
            try expect.toBeTrue(fw.ids.contains(100));
            try expect.toBeTrue(fw.ids.contains(200));
            try expect.toBeTrue(fw.ids.contains(300));
            try expect.toBeTrue(fw.ids.contains(400));
        }

        test "finds paths using entity IDs" {
            try expect.toBeTrue(fw.hasPathWithMapping(100, 400));
            try expect.toBeTrue(fw.hasPathWithMapping(100, 200));
            try expect.toBeTrue(fw.hasPathWithMapping(200, 300));
        }

        test "calculates distances using entity IDs" {
            try expect.equal(fw.valueWithMapping(100, 200), 1);
            try expect.equal(fw.valueWithMapping(100, 300), 2);
            try expect.equal(fw.valueWithMapping(100, 400), 3);
        }

        test "returns correct next hop in path" {
            try expect.equal(fw.nextWithMapping(100, 400), 200);
            try expect.equal(fw.nextWithMapping(200, 400), 300);
            try expect.equal(fw.nextWithMapping(300, 400), 400);
        }

        test "reconstructs full path" {
            var path_list = std.ArrayListUnmanaged(u32){};
            defer path_list.deinit(std.testing.allocator);

            try fw.setPathWithMappingUnmanaged(std.testing.allocator, &path_list, 100, 400);

            try expect.equal(path_list.items.len, 4);
            try expect.equal(path_list.items[0], 100);
            try expect.equal(path_list.items[1], 200);
            try expect.equal(path_list.items[2], 300);
            try expect.equal(path_list.items[3], 400);
        }
    };

    pub const @"weighted edges" = struct {
        test "tests:before" {
            fw.resize(4);
            try fw.clean();
            // Create graph with different weights:
            // 0 --5--> 1 --3--> 3
            // 0 --2--> 2 --2--> 3
            fw.addEdge(0, 1, 5);
            fw.addEdge(1, 3, 3);
            fw.addEdge(0, 2, 2);
            fw.addEdge(2, 3, 2);
            fw.generate();
        }

        test "finds shortest path through lower weight route" {
            // 0 -> 2 -> 3 = 4 is shorter than 0 -> 1 -> 3 = 8
            try expect.equal(fw.value(0, 3), 4);
        }

        test "next hop follows shortest path" {
            // Should go through node 2, not node 1
            try expect.equal(fw.getNext(0, 3), 2);
        }
    };

    pub const @"clean and reset" = struct {
        test "tests:before" {
            fw.resize(3);
            try fw.clean();
            fw.addEdgeWithMapping(10, 20, 1);
            fw.generate();
        }

        test "resets the graph when clean is called" {
            try expect.toBeTrue(fw.hasPathWithMapping(10, 20));

            // Clean and reconfigure
            try fw.clean();

            // Old mappings should be gone
            try expect.toBeFalse(fw.ids.contains(10));
            try expect.toBeFalse(fw.ids.contains(20));
            try expect.equal(fw.last_key, 0);
        }
    };

    pub const @"SIMD handles non-aligned sizes" = struct {
        test "tests:before" {
            // Use a size that's not a multiple of SIMD vector width (4)
            fw.resize(7);
            try fw.clean();
            // Create a complete graph
            var i: u32 = 0;
            while (i < 7) : (i += 1) {
                var j: u32 = 0;
                while (j < 7) : (j += 1) {
                    if (i != j) {
                        fw.addEdge(i, j, 1);
                    }
                }
            }
            fw.generate();
        }

        test "correctly computes paths for non-aligned matrix size" {
            // All nodes should be reachable from all other nodes
            try expect.toBeTrue(fw.hasPath(0, 6));
            try expect.toBeTrue(fw.hasPath(6, 0));
            try expect.toBeTrue(fw.hasPath(3, 5));

            // Direct connections should have distance 1
            try expect.equal(fw.value(0, 1), 1);
            try expect.equal(fw.value(5, 6), 1);
        }
    };
};

/// Test engine with optimized Floyd-Warshall
pub const EngineOptimizedSpec = struct {
    const TestConfig = struct {
        pub const Entity = u32;
        pub const Context = void;
        pub const floyd_warshall_variant = pathfinding.FloydWarshallVariant.optimized_simd;
    };

    var engine: pathfinding.PathfindingEngine(TestConfig) = undefined;

    test "tests:before" {
        engine = try pathfinding.PathfindingEngine(TestConfig).init(std.testing.allocator);
    }

    test "tests:after" {
        engine.deinit();
    }

    pub const @"engine with optimized FW" = struct {
        test "tests:before" {
            // Add nodes
            try engine.addNode(0, 0, 0);
            try engine.addNode(1, 100, 0);
            try engine.addNode(2, 200, 0);
            try engine.addNode(3, 200, 100);

            // Connect nodes
            try engine.connectNodes(.{ .omnidirectional = .{ .max_distance = 150, .max_connections = 4 } });

            // Rebuild paths
            try engine.rebuildPaths();
        }

        test "finds paths between nodes" {
            try expect.toBeTrue(engine.hasPathBetween(0, 3));
            try expect.toBeTrue(engine.hasPathBetween(0, 2));
        }

        test "calculates correct distances" {
            // Distance from 0 to 1 should be ~100
            const dist_0_1 = engine.getPathDistance(0, 1);
            try expect.toBeTrue(dist_0_1 != null);
            try expect.equal(dist_0_1.?, 100);
        }

        test "entity pathfinding works" {
            try engine.registerEntity(1, 0, 0, 100);
            try engine.requestPath(1, 3);

            // Entity should exist and be at starting position
            const pos = engine.getPosition(1);
            try expect.toBeTrue(pos != null);
            try expect.equal(pos.?.x, 0);
            try expect.equal(pos.?.y, 0);
        }
    };
};
