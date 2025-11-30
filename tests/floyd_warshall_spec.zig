const std = @import("std");
const zspec = @import("zspec");
const pathfinding = @import("pathfinding");

const expect = zspec.expect;

pub const FloydWarshallSpec = struct {
    var fw: pathfinding.FloydWarshall = undefined;

    test "tests:before" {
        fw = pathfinding.FloydWarshall.init(std.testing.allocator);
    }

    test "tests:after" {
        fw.deinit();
    }

    pub const @"initialization" = struct {
        test "creates with default size" {
            try expect.equal(fw.last_key, 0);
            try expect.equal(fw.size, 100);
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
            var path_list = std.array_list.Managed(u32).init(std.testing.allocator);
            defer path_list.deinit();

            try fw.setPathWithMapping(&path_list, 100, 400);

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
            try expect.equal(fw.next(0, 3), 2);
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
};
