/*
 * step-convert: Convert STEP files to STL using OpenCASCADE.
 *
 * Usage:
 *   step-convert <input.step> <output.stl> [--info] [--split]
 *
 * With --info, outputs metadata JSON to stderr.
 * With --split, outputs each solid as a separate STL file:
 *   output_0.stl, output_1.stl, etc.
 *   Solid names (from STEP labels) are included in --info JSON.
 */

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include <STEPControl_Reader.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <StlAPI_Writer.hxx>
#include <BRep_Builder.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Compound.hxx>
#include <TopoDS_Shape.hxx>
#include <TopoDS_Solid.hxx>
#include <TopExp_Explorer.hxx>
#include <Bnd_Box.hxx>
#include <BRepBndLib.hxx>
#include <Interface_Static.hxx>
#include <XSControl_WorkSession.hxx>
#include <XSControl_TransferReader.hxx>
#include <Transfer_TransientProcess.hxx>
#include <Transfer_Binder.hxx>
#include <TransferBRep.hxx>
#include <StepShape_ShapeRepresentation.hxx>
#include <TCollection_HAsciiString.hxx>

struct SolidInfo {
    TopoDS_Shape shape;
    std::string name;
    int faces;
};

// Try to extract STEP entity name for a shape
static std::string getShapeName(const STEPControl_Reader &reader, const TopoDS_Shape &shape) {
    try {
        Handle(XSControl_WorkSession) ws = reader.WS();
        if (ws.IsNull()) return "";
        Handle(XSControl_TransferReader) tr = ws->TransferReader();
        if (tr.IsNull()) return "";
        Handle(Transfer_TransientProcess) tp = tr->TransientProcess();
        if (tp.IsNull()) return "";

        // Find the STEP entity for this shape
        Standard_Integer nb = tp->NbMapped();
        for (Standard_Integer i = 1; i <= nb; i++) {
            Handle(Transfer_Binder) binder = tp->MapItem(i);
            if (binder.IsNull()) continue;
            TopoDS_Shape result = TransferBRep::ShapeResult(binder);
            if (result.IsNull() || !result.IsSame(shape)) continue;

            Handle(Standard_Transient) ent = tp->Mapped(i);
            Handle(StepShape_ShapeRepresentation) sr = Handle(StepShape_ShapeRepresentation)::DownCast(ent);
            if (!sr.IsNull() && !sr->Name().IsNull()) {
                return sr->Name()->ToCString();
            }
        }
    } catch (...) {}
    return "";
}

int main(int argc, char *argv[]) {
    if (argc < 3) {
        fprintf(stderr, "Usage: step-convert <input.step> <output.stl> [--info] [--split]\n");
        return 1;
    }

    const char *input_path = argv[1];
    const char *output_path = argv[2];
    bool emit_info = false;
    bool split_mode = false;

    for (int i = 3; i < argc; i++) {
        if (strcmp(argv[i], "--info") == 0) emit_info = true;
        if (strcmp(argv[i], "--split") == 0) split_mode = true;
    }

    // Read STEP file
    STEPControl_Reader reader;
    IFSelect_ReturnStatus status = reader.ReadFile(input_path);
    if (status != IFSelect_RetDone) {
        fprintf(stderr, "Error: failed to read STEP file: %s\n", input_path);
        return 1;
    }

    // Transfer all roots
    reader.TransferRoots();
    int nb_shapes = reader.NbShapes();

    if (nb_shapes == 0) {
        fprintf(stderr, "Error: no shapes found in STEP file\n");
        return 1;
    }

    // Collect all solids
    std::vector<SolidInfo> solids;
    for (int i = 1; i <= nb_shapes; i++) {
        TopoDS_Shape shape = reader.Shape(i);
        for (TopExp_Explorer exp(shape, TopAbs_SOLID); exp.More(); exp.Next()) {
            SolidInfo info;
            info.shape = exp.Current();
            info.name = getShapeName(reader, exp.Current());
            info.faces = 0;
            for (TopExp_Explorer fexp(info.shape, TopAbs_FACE); fexp.More(); fexp.Next()) {
                info.faces++;
            }
            solids.push_back(info);
        }
        // If no solids found, treat the whole shape as one entry
        if (solids.empty()) {
            SolidInfo info;
            info.shape = shape;
            info.name = getShapeName(reader, shape);
            info.faces = 0;
            for (TopExp_Explorer fexp(shape, TopAbs_FACE); fexp.More(); fexp.Next()) {
                info.faces++;
            }
            solids.push_back(info);
        }
    }

    // Name unnamed solids
    for (size_t i = 0; i < solids.size(); i++) {
        if (solids[i].name.empty()) {
            solids[i].name = "Solid_" + std::to_string(i);
        }
    }

    // Compute overall bounding box
    Bnd_Box bbox;
    int total_faces = 0;
    for (auto &s : solids) {
        BRepBndLib::Add(s.shape, bbox);
        total_faces += s.faces;
    }
    double xmin = 0, ymin = 0, zmin = 0, xmax = 0, ymax = 0, zmax = 0;
    if (!bbox.IsVoid()) {
        bbox.Get(xmin, ymin, zmin, xmax, ymax, zmax);
    }

    if (split_mode && solids.size() > 1) {
        // Write each solid as a separate STL file
        std::string base(output_path);
        // Strip .stl extension
        if (base.size() > 4 && base.substr(base.size() - 4) == ".stl") {
            base = base.substr(0, base.size() - 4);
        }

        for (size_t i = 0; i < solids.size(); i++) {
            BRepMesh_IncrementalMesh mesh(solids[i].shape, 0.1);
            mesh.Perform();

            std::string path = base + "_" + std::to_string(i) + ".stl";
            StlAPI_Writer writer;
            writer.ASCIIMode() = Standard_False;
            writer.Write(solids[i].shape, path.c_str());
        }
    } else {
        // Single output: combine all shapes
        BRep_Builder builder;
        TopoDS_Compound compound;
        builder.MakeCompound(compound);
        for (auto &s : solids) {
            builder.Add(compound, s.shape);
        }

        BRepMesh_IncrementalMesh mesh(compound, 0.1);
        mesh.Perform();

        StlAPI_Writer writer;
        writer.ASCIIMode() = Standard_False;
        if (!writer.Write(compound, output_path)) {
            fprintf(stderr, "Error: failed to write STL to %s\n", output_path);
            return 1;
        }
    }

    // Output metadata JSON to stderr
    if (emit_info) {
        fprintf(stderr, "{\"file\":\"%s\",\"shapes\":%d,\"solids\":%d,\"faces\":%d,"
                "\"bounds\":{\"min_x\":%.4f,\"min_y\":%.4f,\"min_z\":%.4f,"
                "\"max_x\":%.4f,\"max_y\":%.4f,\"max_z\":%.4f},"
                "\"width\":%.2f,\"height\":%.2f,\"depth\":%.2f,\"unit\":\"mm\","
                "\"parts\":[",
                input_path, nb_shapes, (int)solids.size(), total_faces,
                xmin, ymin, zmin, xmax, ymax, zmax,
                xmax - xmin, ymax - ymin, zmax - zmin);
        for (size_t i = 0; i < solids.size(); i++) {
            if (i > 0) fprintf(stderr, ",");
            fprintf(stderr, "{\"name\":\"%s\",\"faces\":%d}", solids[i].name.c_str(), solids[i].faces);
        }
        fprintf(stderr, "]}\n");
    }

    printf("%s\n", output_path);
    return 0;
}
