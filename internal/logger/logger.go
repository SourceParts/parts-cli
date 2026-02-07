package logger

import (
	"fmt"
	"log"
	"os"
)

// Logger provides conditional logging based on verbosity
type Logger struct {
	verbose *bool
	logger  *log.Logger
}

// New creates a new Logger instance
func New(verbose *bool) *Logger {
	return &Logger{
		verbose: verbose,
		logger:  log.New(os.Stderr, "[parts] ", log.LstdFlags),
	}
}

// Printf prints a formatted message if verbose mode is enabled
func (l *Logger) Printf(format string, v ...interface{}) {
	if l.verbose != nil && *l.verbose {
		l.logger.Printf(format, v...)
	}
}

// Println prints a message if verbose mode is enabled
func (l *Logger) Println(v ...interface{}) {
	if l.verbose != nil && *l.verbose {
		l.logger.Println(v...)
	}
}

// Errorf prints an error message (always shown)
func Errorf(format string, v ...interface{}) {
	fmt.Fprintf(os.Stderr, "Error: "+format+"\n", v...)
}

// Printf prints a formatted message (for package-level use)
func Printf(format string, v ...interface{}) {
	fmt.Printf(format+"\n", v...)
}
