// usbc-gen.cpp — Generate USB-C 16P waterproof connector STEP file
// Uses OpenCASCADE (same libs as step-convert)
//
// Build:
//   c++ -std=c++17 -o tools/usbc-gen tools/usbc-gen.cpp \
//     -I/opt/homebrew/include/opencascade -L/opt/homebrew/lib \
//     -lTKDESTEP -lTKBRep -lTKernel -lTKG3d -lTKTopAlgo \
//     -lTKMath -lTKGeomBase -lTKPrim -lTKBO -lTKFillet \
//     -lTKXSBase -lTKGeomAlgo -lTKShHealing -lTKOffset
//
// Run:
//   ./tools/usbc-gen output.step

#include <BRepPrimAPI_MakeBox.hxx>
#include <BRepPrimAPI_MakeCylinder.hxx>
#include <BRepPrimAPI_MakePrism.hxx>
#include <BRepBuilderAPI_MakeEdge.hxx>
#include <BRepBuilderAPI_MakeWire.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepBuilderAPI_Transform.hxx>
#include <BRepFilletAPI_MakeFillet.hxx>
#include <BRepAlgoAPI_Cut.hxx>
#include <BRepAlgoAPI_Fuse.hxx>
#include <GC_MakeArcOfCircle.hxx>
#include <TopoDS_Shape.hxx>
#include <TopoDS.hxx>
#include <TopExp_Explorer.hxx>
#include <gp_Pnt.hxx>
#include <gp_Ax2.hxx>
#include <gp_Vec.hxx>
#include <gp_Trsf.hxx>
#include <STEPControl_Writer.hxx>
#include <Interface_Static.hxx>
#include <iostream>
#include <string>
#include <cmath>

// =============================================================
// All dimensions in mm — from 防水TYPE-C 16P datasheet
// =============================================================

// Shell outer (SUS304 stainless steel)
static constexpr double SHELL_W = 8.94;     // receptacle width (USB-C standard)
static constexpr double SHELL_H = 3.32;     // receptacle height
static constexpr double SHELL_L = 9.12;     // shell length (mating direction)
static constexpr double SHELL_R = 0.64;     // corner radius (USB-C spec)
static constexpr double SHELL_WALL = 0.30;  // wall thickness

// Overall body
static constexpr double BODY_L = 9.92;      // total length
static constexpr double BODY_W = 8.34;      // total width
static constexpr double BODY_H = 3.50;      // height above PCB

// Tongue / center insert
static constexpr double TONGUE_L = 6.65;    // tongue length into receptacle
static constexpr double TONGUE_W = 7.00;    // tongue width
static constexpr double TONGUE_H = 0.19;    // tongue thickness (PCB insert)

// Mounting legs (zinc alloy, 2x)
static constexpr double LEG_W = 1.30;       // leg width
static constexpr double LEG_D = 1.00;       // leg depth (front-to-back)
static constexpr double LEG_H = 3.50;       // leg height above PCB
static constexpr double LEG_SPACING = 7.45; // center-to-center

// Pins (16 total, 2 rows of 8)
static constexpr double PIN_W = 0.25;       // pin width
static constexpr double PIN_D = 0.25;       // pin depth
static constexpr double PIN_VERT_H = 1.30;  // vertical segment height (inside housing to PCB)
static constexpr double PIN_TAIL_L = 1.86;  // horizontal SMD tail length
static constexpr double PIN_TAIL_H = 0.20;  // tail thickness
static constexpr double PIN_PITCH = 0.50;   // USB-C standard pitch
static constexpr double PIN_ROW_GAP = 0.50; // half-gap between rows (center to row center)

// O-ring groove
static constexpr double ORING_DEPTH = 0.30; // groove depth into shell
static constexpr double ORING_WIDTH = 0.80; // groove width along X
static constexpr double ORING_OFFSET = 1.50;// from front face

// =============================================================
// Rounded rectangle wire profile in YZ plane
// =============================================================

TopoDS_Wire makeRoundedRect(double w, double h, double r) {
    // Centered on origin in YZ plane
    // w = total width (Y), h = total height (Z), r = corner radius
    double hw = w / 2.0;
    double hh = h / 2.0;

    // Corner centers
    gp_Pnt c1( 0, hw - r,  hh - r);  // top-right
    gp_Pnt c2( 0, -hw + r, hh - r);  // top-left
    gp_Pnt c3( 0, -hw + r, -hh + r); // bottom-left
    gp_Pnt c4( 0, hw - r,  -hh + r); // bottom-right

    // Corner arc endpoints (clockwise from top-right)
    gp_Pnt p1(0, hw,      hh - r);  // right side, start of top-right arc
    gp_Pnt p2(0, hw - r,  hh);      // top side, end of top-right arc
    gp_Pnt p3(0, -hw + r, hh);      // top side, start of top-left arc
    gp_Pnt p4(0, -hw,     hh - r);  // left side, end of top-left arc
    gp_Pnt p5(0, -hw,     -hh + r); // left side, start of bottom-left arc
    gp_Pnt p6(0, -hw + r, -hh);     // bottom, end of bottom-left arc
    gp_Pnt p7(0, hw - r,  -hh);     // bottom, start of bottom-right arc
    gp_Pnt p8(0, hw,      -hh + r); // right side, end of bottom-right arc

    // Mid-points for arcs
    double rm = r * (1.0 - 1.0 / std::sqrt(2.0));
    gp_Pnt m1(0, hw - rm,      hh - rm);
    gp_Pnt m2(0, -hw + rm,     hh - rm);
    gp_Pnt m3(0, -hw + rm,     -hh + rm);
    gp_Pnt m4(0, hw - rm,      -hh + rm);

    BRepBuilderAPI_MakeWire wireBuilder;

    // Right edge (bottom to top)
    wireBuilder.Add(BRepBuilderAPI_MakeEdge(p8, p1).Edge());
    // Top-right arc
    wireBuilder.Add(BRepBuilderAPI_MakeEdge(GC_MakeArcOfCircle(p1, m1, p2).Value()).Edge());
    // Top edge
    wireBuilder.Add(BRepBuilderAPI_MakeEdge(p2, p3).Edge());
    // Top-left arc
    wireBuilder.Add(BRepBuilderAPI_MakeEdge(GC_MakeArcOfCircle(p3, m2, p4).Value()).Edge());
    // Left edge
    wireBuilder.Add(BRepBuilderAPI_MakeEdge(p4, p5).Edge());
    // Bottom-left arc
    wireBuilder.Add(BRepBuilderAPI_MakeEdge(GC_MakeArcOfCircle(p5, m3, p6).Value()).Edge());
    // Bottom edge
    wireBuilder.Add(BRepBuilderAPI_MakeEdge(p6, p7).Edge());
    // Bottom-right arc
    wireBuilder.Add(BRepBuilderAPI_MakeEdge(GC_MakeArcOfCircle(p7, m4, p8).Value()).Edge());

    return wireBuilder.Wire();
}

// Extrude a wire profile along +X
TopoDS_Shape extrudeProfile(const TopoDS_Wire& wire, double length) {
    TopoDS_Face face = BRepBuilderAPI_MakeFace(wire).Face();
    return BRepPrimAPI_MakePrism(face, gp_Vec(length, 0, 0)).Shape();
}

// Translate a shape
TopoDS_Shape translate(const TopoDS_Shape& shape, double dx, double dy, double dz) {
    gp_Trsf trsf;
    trsf.SetTranslation(gp_Vec(dx, dy, dz));
    return BRepBuilderAPI_Transform(shape, trsf).Shape();
}

// =============================================================
// Build the connector
// =============================================================

TopoDS_Shape makeShell() {
    // Outer shell: rounded rect extruded along X
    TopoDS_Wire outerWire = makeRoundedRect(SHELL_W, SHELL_H, SHELL_R);
    TopoDS_Shape outer = extrudeProfile(outerWire, SHELL_L);
    // Position: front face at x=SHELL_L/2, back at -SHELL_L/2
    // Center at origin, front pointing +X
    outer = translate(outer, -SHELL_L / 2.0, 0, SHELL_H / 2.0);

    // Inner cavity (slightly smaller, cut from inside)
    double innerW = SHELL_W - 2 * SHELL_WALL;
    double innerH = SHELL_H - 2 * SHELL_WALL;
    double innerR = SHELL_R > SHELL_WALL ? SHELL_R - SHELL_WALL : 0.1;
    TopoDS_Wire innerWire = makeRoundedRect(innerW, innerH, innerR);
    TopoDS_Shape inner = extrudeProfile(innerWire, SHELL_L + 0.2);
    inner = translate(inner, -SHELL_L / 2.0 - 0.1, 0, SHELL_H / 2.0);

    return BRepAlgoAPI_Cut(outer, inner).Shape();
}

TopoDS_Shape makeTongue() {
    BRepPrimAPI_MakeBox box(
        gp_Pnt(SHELL_L / 2.0 - TONGUE_L, -TONGUE_W / 2.0, SHELL_H / 2.0 - TONGUE_H / 2.0),
        TONGUE_L, TONGUE_W, TONGUE_H
    );
    return box.Shape();
}

TopoDS_Shape makeHousing() {
    double housingL = BODY_L - SHELL_L;
    BRepPrimAPI_MakeBox box(
        gp_Pnt(-BODY_L / 2.0, -BODY_W / 2.0, 0),
        housingL, BODY_W, BODY_H
    );

    // Try to fillet the vertical edges
    TopoDS_Shape housing = box.Shape();
    try {
        BRepFilletAPI_MakeFillet fillet(housing);
        int count = 0;
        TopExp_Explorer explorer(housing, TopAbs_EDGE);
        while (explorer.More() && count < 4) {
            TopoDS_Edge edge = TopoDS::Edge(explorer.Current());
            fillet.Add(0.5, edge);
            explorer.Next();
            count++;
        }
        if (fillet.IsDone()) return fillet.Shape();
    } catch (...) {}

    return housing;
}

TopoDS_Shape makeMountingLeg(double yCenter) {
    BRepPrimAPI_MakeBox leg(
        gp_Pnt(-2.0 - LEG_D / 2.0, yCenter - LEG_W / 2.0, 0),
        LEG_D, LEG_W, LEG_H
    );
    return leg.Shape();
}

TopoDS_Shape makeLShapedPin(double x, double y) {
    // Vertical segment: rises from PCB surface (Z=0) up into housing
    BRepPrimAPI_MakeBox vert(
        gp_Pnt(x - PIN_W / 2.0, y - PIN_D / 2.0, 0),
        PIN_W, PIN_D, PIN_VERT_H
    );

    // Horizontal SMD tail: extends behind connector, sitting on PCB (Z=0)
    BRepPrimAPI_MakeBox tail(
        gp_Pnt(x - PIN_W / 2.0 - PIN_TAIL_L, y - PIN_D / 2.0, 0),
        PIN_TAIL_L, PIN_D, PIN_TAIL_H
    );

    return BRepAlgoAPI_Fuse(vert.Shape(), tail.Shape()).Shape();
}

TopoDS_Shape makeORingGroove(double shellH, double shellW, double shellR) {
    // Annular groove cut around the front face of the shell
    // Outer ring
    double outerW = shellW + 0.2;
    double outerH = shellH + 0.2;
    TopoDS_Wire outerWire = makeRoundedRect(outerW, outerH, shellR + 0.1);
    TopoDS_Shape outerRing = extrudeProfile(outerWire, ORING_WIDTH);

    // Inner ring (shell profile)
    TopoDS_Wire innerWire = makeRoundedRect(shellW - 2 * ORING_DEPTH, shellH - 2 * ORING_DEPTH, shellR > ORING_DEPTH ? shellR - ORING_DEPTH : 0.1);
    TopoDS_Shape innerRing = extrudeProfile(innerWire, ORING_WIDTH + 0.2);

    TopoDS_Shape groove = BRepAlgoAPI_Cut(outerRing, innerRing).Shape();
    // Position at front of shell
    return translate(groove, SHELL_L / 2.0 - ORING_OFFSET - ORING_WIDTH, 0, shellH / 2.0);
}

int main(int argc, char* argv[]) {
    std::string outputPath = "usbc-waterproof-16p.step";
    if (argc >= 2) outputPath = argv[1];

    std::cout << "Generating USB-C 16P waterproof connector..." << std::endl;
    std::cout << "  Shell:   " << SHELL_L << " x " << SHELL_W << " x " << SHELL_H << " mm (R=" << SHELL_R << ")" << std::endl;
    std::cout << "  Body:    " << BODY_L << " x " << BODY_W << " x " << BODY_H << " mm" << std::endl;
    std::cout << "  Tongue:  " << TONGUE_L << " x " << TONGUE_W << " x " << TONGUE_H << " mm" << std::endl;
    std::cout << "  Pins:    16 (2x8 @ " << PIN_PITCH << "mm pitch, L-shaped SMD)" << std::endl;

    // Build shell (rounded rectangle, hollowed)
    std::cout << "  [1/6] Shell..." << std::flush;
    TopoDS_Shape shell = makeShell();
    std::cout << " done" << std::endl;

    // Build tongue
    std::cout << "  [2/6] Tongue..." << std::flush;
    TopoDS_Shape tongue = makeTongue();
    std::cout << " done" << std::endl;

    // Build housing
    std::cout << "  [3/6] Housing..." << std::flush;
    TopoDS_Shape housing = makeHousing();
    std::cout << " done" << std::endl;

    // Fuse shell + tongue + housing
    std::cout << "  [4/6] Assembly..." << std::flush;
    BRepAlgoAPI_Fuse f1(shell, tongue);
    BRepAlgoAPI_Fuse f2(f1.Shape(), housing);
    TopoDS_Shape connector = f2.Shape();

    // O-ring groove (cut from shell)
    TopoDS_Shape groove = makeORingGroove(SHELL_H, SHELL_W, SHELL_R);
    connector = BRepAlgoAPI_Cut(connector, groove).Shape();
    std::cout << " done" << std::endl;

    // Mounting legs
    std::cout << "  [5/6] Legs + Pins..." << std::flush;
    TopoDS_Shape leg1 = makeMountingLeg(-LEG_SPACING / 2.0);
    TopoDS_Shape leg2 = makeMountingLeg(LEG_SPACING / 2.0);
    connector = BRepAlgoAPI_Fuse(connector, leg1).Shape();
    connector = BRepAlgoAPI_Fuse(connector, leg2).Shape();

    // 16 L-shaped SMD pins (2 rows of 8)
    double pinStartX = 1.75; // center of first pin from connector center
    for (int i = 0; i < 8; i++) {
        double x = pinStartX - i * PIN_PITCH;
        // Top row (A-side)
        TopoDS_Shape pinA = makeLShapedPin(x, -PIN_ROW_GAP);
        connector = BRepAlgoAPI_Fuse(connector, pinA).Shape();
        // Bottom row (B-side)
        TopoDS_Shape pinB = makeLShapedPin(x, PIN_ROW_GAP);
        connector = BRepAlgoAPI_Fuse(connector, pinB).Shape();
    }
    std::cout << " done" << std::endl;

    // Write STEP
    std::cout << "  [6/6] Writing STEP..." << std::flush;
    STEPControl_Writer writer;
    Interface_Static::SetCVal("xstep.cascade.unit", "MM");
    Interface_Static::SetCVal("write.step.schema", "AP214");

    writer.Transfer(connector, STEPControl_AsIs);
    IFSelect_ReturnStatus status = writer.Write(outputPath.c_str());

    if (status == IFSelect_RetDone) {
        std::cout << " done" << std::endl;
        std::cout << "STEP saved: " << outputPath << std::endl;
        return 0;
    } else {
        std::cerr << " FAILED" << std::endl;
        return 1;
    }
}
