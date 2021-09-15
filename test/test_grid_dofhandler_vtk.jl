# to test vtk-files
using StableRNGs
OVERWRITE_CHECKSUMS = false
checksums_file = joinpath(dirname(@__FILE__), "checksums.sha1")
checksum_list = read(checksums_file, String)
if OVERWRITE_CHECKSUMS
    csio = open(checksums_file, "w")
else
    csio = open(checksums_file, "r")
end

@testset "Grid, DofHandler, vtk" begin
    for (celltype, dim) in ((Line,                   1),
                            (QuadraticLine,          1),
                            (Quadrilateral,          2),
                            (QuadraticQuadrilateral, 2),
                            (Triangle,               2),
                            (QuadraticTriangle,      2),
                            (Hexahedron,             3),
                            (Cell{3,20,6},           3),
                            (Tetrahedron,            3))

        # create test grid, do some operations on it and then test
        # the resulting sha1 of the stored vtk file
        # after manually checking the exported vtk
        nels = ntuple(x->5, dim)
        right = Vec{dim, Float64}(ntuple(x->1.5, dim))
        left = -right
        grid = generate_grid(celltype, nels, left, right)

        transform!(grid, x-> 2x)

        radius = 2*1.5
        addcellset!(grid, "cell-1", [1,])
        addcellset!(grid, "middle-cells", x -> norm(x) < radius)
        addfaceset!(grid, "middle-faceset", x -> norm(x) < radius)
        addfaceset!(grid, "right-faceset", getfaceset(grid, "right"))
        addnodeset!(grid, "middle-nodes", x -> norm(x) < radius)

        gridfilename = "grid-$(Ferrite.celltypes[celltype])"
        vtk_grid(gridfilename, grid) do vtk
            vtk_cellset(vtk, grid, "cell-1")
            vtk_cellset(vtk, grid, "middle-cells")
            vtk_nodeset(vtk, grid, "middle-nodes")
        end

        # test the sha of the file
        sha = bytes2hex(open(SHA.sha1, gridfilename*".vtu"))
        if OVERWRITE_CHECKSUMS
            write(csio, sha, "\n")
        else
            @test chomp(readline(csio)) == sha
            rm(gridfilename*".vtu")
        end

        # Create a DofHandler, add some things, write to file and
        # then check the resulting sha
        dofhandler = DofHandler(grid)
        push!(dofhandler, :temperature, 1)
        push!(dofhandler, :displacement, 3)
        close!(dofhandler)
        ch = ConstraintHandler(dofhandler)
        dbc = Dirichlet(:temperature, union(getfaceset(grid, "left"), getfaceset(grid, "right-faceset")), (x,t)->1)
        add!(ch, dbc)
        dbc = Dirichlet(:temperature, getfaceset(grid, "middle-faceset"), (x,t)->4)
        add!(ch, dbc)
        for d in 1:dim
            dbc = Dirichlet(:displacement, union(getfaceset(grid, "left")), (x,t) -> d, d)
            add!(ch, dbc)
        end
        close!(ch)
        update!(ch, 0.0)
        rng = StableRNG(1234)
        u = rand(rng, ndofs(dofhandler))
        apply!(u, ch)

        dofhandlerfilename = "dofhandler-$(Ferrite.celltypes[celltype])"
        vtk_grid(dofhandlerfilename, dofhandler) do vtk
            vtk_point_data(vtk, ch)
            vtk_point_data(vtk, dofhandler, u)
        end

        # test the sha of the file
        sha = bytes2hex(open(SHA.sha1, dofhandlerfilename*".vtu"))
        if OVERWRITE_CHECKSUMS
            write(csio, sha, "\n")
        else
            @test chomp(readline(csio)) == sha
            rm(dofhandlerfilename*".vtu")
        end

    end

end # of testset

close(csio)


# right = Vec{2, Float64}(ntuple(x->1.5, dim))
# left = -right

@testset "Grid utils" begin

    grid = Ferrite.generate_grid(QuadraticQuadrilateral, (1, 1), Vec((0.,0.)), Vec((1.,1.)))

    addcellset!(grid, "cell_set", [1]);
    node_set = Set(1:getnnodes(grid))
    addnodeset!(grid, "node_set", node_set)

    @test getnodesets(grid) == Dict("node_set" => node_set)

    @test getnodes(grid, [1]) == [getnodes(grid, 1)] # untested

    @test length(getnodes(grid, "node_set")) == 9

    @test collect(getcoordinates(getnodes(grid, 5)).data) ≈ [0.5, 0.5]

    @test getcells(grid, "cell_set") == [getcells(grid, 1)]

    f(x) = Tensor{1,1,Float64}((1 + x[1]^2 + 2x[2]^2, ))

    values = compute_vertex_values(grid, f)
    @test f([0.0, 0.0]) == values[1]
    @test f([0.5, 0.5]) == values[5]
    @test f([1.0, 1.0]) == values[9]

    @test compute_vertex_values(grid, collect(1:9), f) == values

    # Can we test this in a better way? The set makes the order random.
    @test length(compute_vertex_values(grid, "node_set", f)) == 9

    # CellIterator on a grid without DofHandler
    grid = generate_grid(Triangle, (4,4))
    n = 0
    ci = CellIterator(grid)
    @test length(ci) == getncells(grid)
    for c in ci
        getcoordinates(c)
        getnodes(c)
        n += cellid(c)
    end
    @test n == div(getncells(grid)*(getncells(grid) + 1), 2)
end

@testset "Grid sets" begin

    grid = Ferrite.generate_grid(Hexahedron, (1, 1, 1), Vec((0.,0., 0.)), Vec((1.,1.,1.)))

    #Test manual add
    addcellset!(grid, "cell_set", [1]);
    addnodeset!(grid, "node_set", [1])
    addfaceset!(grid, "face_set", [FaceIndex(1,1)])
    addedgeset!(grid, "edge_set", [EdgeIndex(1,1)])
    addvertexset!(grid, "vert_set", [VertexIndex(1,1)])

    #Test function add
    addfaceset!(grid, "left_face", (x)-> x[1] ≈ 0.0)
    addedgeset!(grid, "left_lower_edge", (x)-> x[1] ≈ 0.0 && x[3] ≈ 0.0)
    addvertexset!(grid, "left_corner", (x)-> x[1] ≈ 0.0 && x[2] ≈ 0.0 && x[3] ≈ 0.0)

    @test 1 in Ferrite.getnodeset(grid, "node_set")
    @test FaceIndex(1,5) in getfaceset(grid, "left_face")
    @test EdgeIndex(1,4) in getedgeset(grid, "left_lower_edge")
    @test VertexIndex(1,1) in getvertexset(grid, "left_corner")

end

@testset "Grid topology" begin
#                           (11)
#                   (10)+-----+-----+(12)
#                       |  5  |  6  |
#                   (7) +-----+-----+(9)
#                       |  3  |  4  |
#                   (4) +-----+-----+(6)
#                       |  1  |  2  |
#                   (1) +-----+-----+(3)
#                            (2)
    quadgrid = generate_grid(Quadrilateral,(2,3);build_topology=true)
    topology = quadgrid.topology
    #test corner neighbors maps cellid and local corner id to neighbor id and neighbor local corner id
    @test topology.corner_neighbor[1,3] == Ferrite.Neighbor(VertexIndex(4,1))
    @test topology.corner_neighbor[2,4] == Ferrite.Neighbor(VertexIndex(3,2))
    @test topology.corner_neighbor[3,3] == Ferrite.Neighbor(VertexIndex(6,1))
    @test topology.corner_neighbor[3,2] == Ferrite.Neighbor(VertexIndex(2,4))
    @test topology.corner_neighbor[4,1] == Ferrite.Neighbor(VertexIndex(1,3))
    @test topology.corner_neighbor[4,4] == Ferrite.Neighbor(VertexIndex(5,2))
    @test topology.corner_neighbor[5,2] == Ferrite.Neighbor(VertexIndex(4,4))
    @test topology.corner_neighbor[6,1] == Ferrite.Neighbor(VertexIndex(3,3))
    #test face neighbor maps cellid and local face id to neighbor id and neighbor local face id 
    @test topology.face_neighbor[1,2] == Ferrite.Neighbor(FaceIndex(2,4))
    @test topology.face_neighbor[1,3] == Ferrite.Neighbor(FaceIndex(3,1))
    @test topology.face_neighbor[2,3] == Ferrite.Neighbor(FaceIndex(4,1))
    @test topology.face_neighbor[2,4] == Ferrite.Neighbor(FaceIndex(1,2))
    @test topology.face_neighbor[3,1] == Ferrite.Neighbor(FaceIndex(1,3))
    @test topology.face_neighbor[3,2] == Ferrite.Neighbor(FaceIndex(4,4))
    @test topology.face_neighbor[3,3] == Ferrite.Neighbor(FaceIndex(5,1))
    @test topology.face_neighbor[4,1] == Ferrite.Neighbor(FaceIndex(2,3))
    @test topology.face_neighbor[4,3] == Ferrite.Neighbor(FaceIndex(6,1))
    @test topology.face_neighbor[4,4] == Ferrite.Neighbor(FaceIndex(3,2))
    @test topology.face_neighbor[5,1] == Ferrite.Neighbor(FaceIndex(3,3))
    @test topology.face_neighbor[5,2] == Ferrite.Neighbor(FaceIndex(6,4))
    @test topology.face_neighbor[5,3] == Ferrite.Neighbor(Ferrite.BoundaryIndex[])
    @test topology.face_neighbor[5,4] == Ferrite.Neighbor(Ferrite.BoundaryIndex[])
    @test topology.face_neighbor[6,1] == Ferrite.Neighbor(FaceIndex(4,3))
    @test topology.face_neighbor[6,2] == Ferrite.Neighbor(Ferrite.BoundaryIndex[])
    @test topology.face_neighbor[6,3] == Ferrite.Neighbor(Ferrite.BoundaryIndex[])
    @test topology.face_neighbor[6,4] == Ferrite.Neighbor(FaceIndex(5,2))
#                         (8)
#                (7) +-----+-----+(9)
#                    |  3  |  4  |
#                (4) +-----+-----+(6) bottom view
#                    |  1  |  2  |
#                (1) +-----+-----+(3)
#                         (2)
#                         (15)
#               (16) +-----+-----+(17)
#                    |  3  |  4  |
#               (13) +-----+-----+(15) top view
#                    |  1  |  2  |
#               (10) +-----+-----+(12)
#                        (11)
    hexgrid = generate_grid(Hexahedron,(2,2,1);build_topology=true) 
    topology = hexgrid.topology
    @test topology.edge_neighbor[1,11] == Ferrite.Neighbor(EdgeIndex(4,9))
    @test topology.edge_neighbor[2,12] == Ferrite.Neighbor(EdgeIndex(3,10))
    @test topology.edge_neighbor[3,10] == Ferrite.Neighbor(EdgeIndex(2,12))
    @test topology.edge_neighbor[4,9] == Ferrite.Neighbor(EdgeIndex(1,11))
    @test all(iszero,topology.corner_neighbor)
    @test topology.face_neighbor[1,3] == Ferrite.Neighbor(FaceIndex(2,5))
    @test topology.face_neighbor[1,4] == Ferrite.Neighbor(FaceIndex(3,2))
    @test topology.face_neighbor[2,4] == Ferrite.Neighbor(FaceIndex(4,2))
    @test topology.face_neighbor[2,5] == Ferrite.Neighbor(FaceIndex(1,3))
    @test topology.face_neighbor[3,2] == Ferrite.Neighbor(FaceIndex(1,4))
    @test topology.face_neighbor[3,3] == Ferrite.Neighbor(FaceIndex(4,5))
    @test topology.face_neighbor[4,2] == Ferrite.Neighbor(FaceIndex(2,4))
    @test topology.face_neighbor[4,5] == Ferrite.Neighbor(FaceIndex(3,3))

#                   +-----+-----+
#                   |\  6 |\  8 |
#                   |  \  |  \  |
#                   |  5 \| 7  \|
#                   +-----+-----+
#                   |\  2 |\  4 |
#                   |  \  |  \  |
#                   |  1 \| 3  \|
#                   +-----+-----+
# test for multiple corner_neighbors as in e.g. ele 3, local corner 3 (middle node)
    trigrid = generate_grid(Triangle,(2,2);build_topology=true)
    topology = trigrid.topology
    @test topology.corner_neighbor[3,3] == Ferrite.Neighbor([VertexIndex(5,2),VertexIndex(6,1),VertexIndex(7,1)])

# test mixed grid
    cells = [
        Hexahedron((1, 2, 3, 4, 5, 6, 7, 8)),
        Quadrilateral((3, 2, 9, 10)),
        ]
    nodes = [Node(coord) for coord in zeros(Vec{2,Float64}, 10)]
    grid = Grid(cells, nodes, topology=Ferrite.GridTopology(cells))
    topology = grid.topology
    @test all(iszero,topology.corner_neighbor)
# currently, we have in a getdim(cell) != getdim(neighbor_cell) case an unsymmetric topology sparse matrix
# this implies that the neighborhood info is different from the perspective of the cells
# cell 2 is connected via its face, which is an edge for cell 1 and vice versa
    @test topology.face_neighbor[2,1] == Ferrite.Neighbor(EdgeIndex(1,2))
    @test topology.edge_neighbor[1,2] == Ferrite.Neighbor(FaceIndex(2,1))
end
