all:
	dune build

install:
	dune build @install && dune install

test:
	dune runtest

clean:
	dune clean

format:
	dune build @fmt --auto-promote

.PHONY: all gospel why3gospel vocal clean format headers
