package commands

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/SourceParts/parts-cli/internal/domain"
	"github.com/spf13/cobra"
)

// =============================================================================
// CAD Parent Command
// =============================================================================
//
// Wraps /v1/cad/step/*, the OpenCascade-backed STEP/BREP edit surface. These
// endpoints shipped without any CLI client — the MCP was the only caller, so an
// MCP outage took the whole CAD surface with it.
//
// Unlike the /v1/eda/* exports, these routes answer with a RAW BINARY body and
// a Content-Disposition header, not the {status,data} JSON envelope. Only
// `inspect` returns JSON. writeExportResult is therefore not usable here.

var CAD = &cobra.Command{
	Use:   "cad",
	Short: "Parametric STEP/BREP editing and conversion",
	Long: `Inspect, edit and convert CAD files server-side via OpenCascade.

Subcommands:
  inspect     Report bounding box, topology, volume and centre of mass
  convert     Convert between step, stl, obj, amf, dxf, gltf
  transform   Translate or rotate a shape
  boolean     Cut, union or intersect against a primitive
  feature     Drill, boss, fillet or chamfer
  pattern     Mirror or linear-pattern a feature
  pipeline    Apply a chain of operations in one call

Input formats:  step, stp, brep, stl (max 100 MB)
Output formats: step, stl, obj, amf, dxf, gltf`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

var (
	cadOutput       string
	cadOutputFormat string
	cadOpJSON       string
	cadTargetFormat string
	cadPipelineFile string
)

const cadTimeout = 5 * time.Minute

var cadOutputFormats = []string{"step", "stl", "obj", "amf", "dxf", "gltf"}

func cadValidateOutputFormat(f string) error {
	for _, ok := range cadOutputFormats {
		if f == ok {
			return nil
		}
	}
	return fmt.Errorf("output format %q not supported; expected one of: %s",
		f, strings.Join(cadOutputFormats, ", "))
}

// cadCheckInput verifies the file exists and carries an extension the API
// accepts. The server infers source format from the extension, so a wrong one
// is silently treated as STEP rather than rejected — catch it here instead.
func cadCheckInput(path string) error {
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return fmt.Errorf("file not found: %s", path)
	}
	ext := strings.ToLower(filepath.Ext(path))
	switch ext {
	case ".step", ".stp", ".brep", ".stl":
		return nil
	}
	return fmt.Errorf("unsupported input %q; expected .step, .stp, .brep or .stl", ext)
}

// cadDefaultOutput derives an output path when -o was not given.
func cadDefaultOutput(in, format string) string {
	base := strings.TrimSuffix(filepath.Base(in), filepath.Ext(in))
	return base + "." + format
}

// cadWriteBinary saves a raw response body, or reports the JSON error the API
// returns when something went wrong. Errors come back as JSON even though the
// success path is binary, so sniff before writing.
func cadWriteBinary(data []byte, output string) error {
	if len(data) > 0 && data[0] == '{' {
		var e struct {
			Status string `json:"status"`
			Error  string `json:"error"`
		}
		if json.Unmarshal(data, &e) == nil && e.Error != "" {
			return fmt.Errorf("%s", e.Error)
		}
	}
	if err := os.WriteFile(output, data, 0644); err != nil {
		return fmt.Errorf("failed to write %s: %w", output, err)
	}
	fmt.Printf("Saved: %s (%d bytes)\n", output, len(data))
	return nil
}

// cadRunOp posts a single-op route and saves the binary result.
func cadRunOp(endpoint, inFile, opJSON, outFile, outFormat string) error {
	if err := cadCheckInput(inFile); err != nil {
		return err
	}
	if err := cadValidateOutputFormat(outFormat); err != nil {
		return err
	}
	if strings.TrimSpace(opJSON) == "" {
		return fmt.Errorf("--op is required (JSON operation descriptor)")
	}
	var probe map[string]interface{}
	if err := json.Unmarshal([]byte(opJSON), &probe); err != nil {
		return fmt.Errorf("--op is not valid JSON: %w", err)
	}
	if _, ok := probe["kind"]; !ok {
		return fmt.Errorf("--op must contain a \"kind\" field")
	}

	ctx, cancel := context.WithTimeout(context.Background(), cadTimeout)
	defer cancel()

	var buf bytes.Buffer
	err := Client.EDAUpload(ctx, endpoint, inFile, map[string]string{
		"op":            opJSON,
		"output_format": outFormat,
	}, nil, &buf)
	if err != nil {
		return err
	}
	if outFile == "" {
		outFile = cadDefaultOutput(inFile, outFormat)
	}
	return cadWriteBinary(buf.Bytes(), outFile)
}

// =============================================================================
// inspect — the only JSON-returning route
// =============================================================================

var cadInspect = &cobra.Command{
	Use:   "inspect <file>",
	Short: "Report bounding box, topology, volume and centre of mass",
	Long: `Upload a STEP, BREP or STL file and return its geometric metadata:
bounding box, solid/shell/face/edge/vertex counts, volume and centre of mass.

This is the only /v1/cad route that answers with JSON rather than a binary body.`,
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` cad inspect case-top.step`,
	RunE: func(cmd *cobra.Command, args []string) error {
		if err := cadCheckInput(args[0]); err != nil {
			return err
		}
		ctx, cancel := context.WithTimeout(context.Background(), cadTimeout)
		defer cancel()

		var buf bytes.Buffer
		if err := Client.EDAUpload(ctx, domain.Endpoint_CADInspect, args[0], nil, nil, &buf); err != nil {
			return err
		}
		var pretty bytes.Buffer
		if json.Indent(&pretty, buf.Bytes(), "", "  ") == nil {
			fmt.Println(pretty.String())
		} else {
			fmt.Println(buf.String())
		}
		return nil
	},
}

// =============================================================================
// convert
// =============================================================================

var cadConvert = &cobra.Command{
	Use:   "convert <file>",
	Short: "Convert between CAD and mesh formats",
	Long: `Convert a STEP, BREP or STL file into another format server-side.

Output formats: step, stl, obj, amf, dxf, gltf`,
	Args: cobra.ExactArgs(1),
	Example: domain.BinaryName + ` cad convert case-top.step --to stl -o case-top.stl
  ` + domain.BinaryName + ` cad convert case-top.step --to gltf`,
	RunE: func(cmd *cobra.Command, args []string) error {
		if err := cadCheckInput(args[0]); err != nil {
			return err
		}
		if cadTargetFormat == "" {
			return fmt.Errorf("--to is required (%s)", strings.Join(cadOutputFormats, ", "))
		}
		if err := cadValidateOutputFormat(cadTargetFormat); err != nil {
			return err
		}
		ctx, cancel := context.WithTimeout(context.Background(), cadTimeout)
		defer cancel()

		var buf bytes.Buffer
		err := Client.EDAUpload(ctx, domain.Endpoint_CADConvert, args[0], map[string]string{
			"target_format": cadTargetFormat,
		}, nil, &buf)
		if err != nil {
			return err
		}
		out := cadOutput
		if out == "" {
			out = cadDefaultOutput(args[0], cadTargetFormat)
		}
		return cadWriteBinary(buf.Bytes(), out)
	},
}

// =============================================================================
// single-op routes
// =============================================================================

var cadTransform = &cobra.Command{
	Use:   "transform <file>",
	Short: "Translate or rotate a shape",
	Long: `Translate or rotate a shape.

  translate  {"kind":"translate","offset":[x,y,z]}
  rotate     {"kind":"rotate","axis_start":[x,y,z],"axis_end":[x,y,z],"angle_deg":90}`,
	Args: cobra.ExactArgs(1),
	Example: domain.BinaryName + ` cad transform part.step --op '{"kind":"translate","offset":[10,0,0]}'
  ` + domain.BinaryName + ` cad transform part.step --op '{"kind":"rotate","axis_start":[0,0,0],` +
		`"axis_end":[0,0,1],"angle_deg":90}'`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cadRunOp(domain.Endpoint_CADTransform, args[0], cadOpJSON, cadOutput, cadOutputFormat)
	},
}

var cadBoolean = &cobra.Command{
	Use:   "boolean <file>",
	Short: "Cut, union or intersect against a primitive",
	Long: `Apply a boolean operation between the uploaded shape and a primitive
described in the op descriptor.`,
	Args: cobra.ExactArgs(1),
	Example: domain.BinaryName + ` cad boolean case.step --op '{"kind":"cut","shape":` +
		`{"primitive":"cylinder","radius":1.35,"height":10,"at":[62.1,140.5,0]}}'`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cadRunOp(domain.Endpoint_CADBoolean, args[0], cadOpJSON, cadOutput, cadOutputFormat)
	},
}

var cadFeature = &cobra.Command{
	Use:   "feature <file>",
	Short: "Drill, boss, fillet or chamfer",
	Long: `Add or remove a feature.

  drill    {"kind":"drill","radius":R,"depth":D,"at":[x,y,z]}
  boss     {"kind":"boss","outer_radius":R,"inner_radius":r,"height":H,"at":[x,y,z]}
  fillet   {"kind":"fillet","radius":R}      applies to all edges
  chamfer  {"kind":"chamfer","length":L}     applies to all edges`,
	Args: cobra.ExactArgs(1),
	Example: domain.BinaryName + ` cad feature case.step --op '{"kind":"drill","radius":1.1,"depth":6,"at":[4,4,0]}'
  ` + domain.BinaryName + ` cad feature case.step --op '{"kind":"boss","outer_radius":2.2,` +
		`"inner_radius":0.85,"height":5.3,"at":[4,4,0]}'`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cadRunOp(domain.Endpoint_CADFeature, args[0], cadOpJSON, cadOutput, cadOutputFormat)
	},
}

var cadPattern = &cobra.Command{
	Use:   "pattern <file>",
	Short: "Mirror or linear-pattern a feature",
	Args:  cobra.ExactArgs(1),
	Example: domain.BinaryName + ` cad pattern case.step --op '{"kind":"mirror_y","plane_y":17.9}'
  ` + domain.BinaryName + ` cad pattern case.step --op '{"kind":"linear_pattern",` +
		`"feature":{"primitive":"cylinder","radius":1.1,"height":6},"direction":[1,0,0],"spacing":20,"count":4}'`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cadRunOp(domain.Endpoint_CADPattern, args[0], cadOpJSON, cadOutput, cadOutputFormat)
	},
}

// =============================================================================
// pipeline
// =============================================================================

var cadPipeline = &cobra.Command{
	Use:   "pipeline <file>",
	Short: "Apply a chain of operations in one call",
	Long: `Run an ordered chain of operations against a CAD file in a single
request. The pipeline document is JSON:

  {
    "operations": [
      {"kind": "drill", "radius": 1.35, "depth": 10, "at": [62.1, 140.5, 0]},
      {"kind": "boss",  "outer_radius": 2.5, "inner_radius": 1.25,
       "height": 6, "at": [57.59, 43.9, 0]}
    ],
    "output_format": "step"
  }

Supply it with --pipeline, either as a path to a .json file or as inline JSON.
Execution is synchronous and ordered; the maximum chain length is 256 ops.

Operation schemas — exact, and not guessable:

  {"kind":"translate","offset":[x,y,z]}
  {"kind":"rotate","axis_start":[x,y,z],"axis_end":[x,y,z],"angle_deg":90}
  {"kind":"drill","radius":R,"depth":D,"at":[x,y,z]}
  {"kind":"boss","outer_radius":R,"height":H,"at":[x,y,z],"inner_radius":r}
  {"kind":"fillet","radius":R}          {"kind":"chamfer","length":L}
  {"kind":"cut"|"union"|"intersect","shape":<primitive>}
  {"kind":"mirror_y","plane_y":Y}
  {"kind":"linear_pattern","feature":<primitive>,"direction":[x,y,z],
   "spacing":S,"count":N}

<primitive> is cylinder, box or sphere with an optional "at":
  {"primitive":"cylinder","radius":R,"height":H,"at":[x,y,z]}

Coordinates are in the file's own frame — run 'cad inspect' first. An op placed
outside the solid succeeds and changes nothing.`,
	Args: cobra.ExactArgs(1),
	Example: domain.BinaryName + ` cad pipeline shell.step --pipeline ops.json -o case.step
  ` + domain.BinaryName + ` cad pipeline shell.step --pipeline '{"operations":[{"kind":"mirror_y","plane_y":17.9}]}'`,
	RunE: func(cmd *cobra.Command, args []string) error {
		if err := cadCheckInput(args[0]); err != nil {
			return err
		}
		if strings.TrimSpace(cadPipelineFile) == "" {
			return fmt.Errorf("--pipeline is required (a .json file or inline JSON)")
		}

		// Accept either a path or inline JSON, so a chain can be scripted or
		// pasted without a temp file.
		raw := cadPipelineFile
		if !strings.HasPrefix(strings.TrimSpace(raw), "{") {
			b, err := os.ReadFile(raw)
			if err != nil {
				return fmt.Errorf("failed to read pipeline %s: %w", raw, err)
			}
			raw = string(b)
		}

		var doc struct {
			Operations   []map[string]interface{} `json:"operations"`
			OutputFormat string                   `json:"output_format"`
		}
		if err := json.Unmarshal([]byte(raw), &doc); err != nil {
			return fmt.Errorf("pipeline is not valid JSON: %w", err)
		}
		if len(doc.Operations) == 0 {
			return fmt.Errorf("pipeline.operations must be a non-empty array")
		}
		if len(doc.Operations) > 256 {
			return fmt.Errorf("pipeline.operations too long (%d > 256)", len(doc.Operations))
		}
		for i, op := range doc.Operations {
			if _, ok := op["kind"]; !ok {
				return fmt.Errorf("pipeline.operations[%d] has no \"kind\"", i)
			}
		}

		format := doc.OutputFormat
		if format == "" {
			format = "step"
		}
		if err := cadValidateOutputFormat(format); err != nil {
			return err
		}

		ctx, cancel := context.WithTimeout(context.Background(), cadTimeout)
		defer cancel()

		var buf bytes.Buffer
		err := Client.EDAUpload(ctx, domain.Endpoint_CADPipeline, args[0], map[string]string{
			"pipeline": raw,
		}, nil, &buf)
		if err != nil {
			return err
		}
		out := cadOutput
		if out == "" {
			out = cadDefaultOutput(args[0], format)
		}
		fmt.Printf("Applied %d operation(s)\n", len(doc.Operations))
		return cadWriteBinary(buf.Bytes(), out)
	},
}

func init() {
	for _, c := range []*cobra.Command{
		cadConvert, cadTransform, cadBoolean, cadFeature, cadPattern, cadPipeline,
	} {
		c.Flags().StringVarP(&cadOutput, "output", "o", "", "Output file path")
	}
	for _, c := range []*cobra.Command{cadTransform, cadBoolean, cadFeature, cadPattern} {
		c.Flags().StringVar(&cadOpJSON, "op", "", "Operation descriptor as JSON (required)")
		c.Flags().StringVar(&cadOutputFormat, "output-format", "step",
			"Result format: "+strings.Join(cadOutputFormats, ", "))
	}
	cadConvert.Flags().StringVar(&cadTargetFormat, "to", "",
		"Target format: "+strings.Join(cadOutputFormats, ", "))
	cadPipeline.Flags().StringVar(&cadPipelineFile, "pipeline", "",
		"Pipeline document: path to a .json file, or inline JSON")

	CAD.AddCommand(cadInspect)
	CAD.AddCommand(cadConvert)
	CAD.AddCommand(cadTransform)
	CAD.AddCommand(cadBoolean)
	CAD.AddCommand(cadFeature)
	CAD.AddCommand(cadPattern)
	CAD.AddCommand(cadPipeline)
}
