# Revision history for idml-pandoc-reader

## idml-pandoc-reader 0.5.0 (WIP)

* Better implementation for the pretty formatter (`-p` flag), can be useful with some InDesign documents.
* Support for multiple selectors and `id`-based selectors.
* Support for the `id` operator.
* Support for the `join` operator.
* Solved a bug with `mediaobject` and `inlinemediaobjects` that were not well processed by `core.py` and `map.py`. 
* Solved a bug with unwanted role attributes in output: when Pandoc flattens a structure to have only one wrapper instead of several, it doesn't merge the role attributes together. See `lua-filters/roles-to-classes.lua`.
* Wrote better tests for `map.lua` in the dedicated bash script `lua-filters/test/tests.sh`.
* `classes` operator in `map.lua` has a new behavior. It can either remove all classes of the selected element with `false` or only replace the classes with which it was selected with a string attribute.
* Wrote better docs regarding InDesign file formatting.
* `<tab>` elements are converted to `<phrase>` elements with an additional `converted-tab` role through `idml2docbook`.
* Support for endnotes in `idml2docbook`: endnotes are now converted to regular footnotes with `endnote` attribute set to `1`.
* Support for `LineBlock` blocks. Useful for poetry and other cases where linebreaks matter.
* Support for the `merge` operator.
* Basic logging features to debug the `map.lua` filter.
* Fixed a bug with the degree sign `°` regex.
* Benchmark tests were done to try to improve performances with `map.lua`. The only improvement found is an adjustment in the traversal order: `Block` elements are now parsed before `Inline`, with improvements in computing time when parts of the AST are pruned when applying mapping on `Block` elements.
* Better orthotypography with leading and trailing spaces inside of inline elements are moved to the outside of those elements.
* Style overrides are now supported, and can be disabled using the `-g`/`--ignore-overrides` flag option.
* Better slugs are generated to rename paragraph styles and character styles in a robust way.
* `map.py` now has `--to-ods`, `--to-json-template` and `--to-css` flag options which enables different output formats that summarise the properties of each paragraph style and character style in an Hub XML file as [CSSa](https://github.com/le-tex/CSSa).

## idml-pandoc-reader 0.4.2 (2025-08-25)

* Wrote better docs, again.

## idml-pandoc-reader 0.4.1 (2025-08-25)

* Removed a few comments in the code.
* Wrote better docs.

## idml-pandoc-reader 0.4.0 (2025-08-20)

* Mapping functionalities are now written in Lua. That means that they are now format-agnostic, and can work with Pandoc as their only dependency, see `lua-filters/map.lua`.
* `idml2docbook` was updated to reflect those changes, and is now closer to a simple IDML-to-DocBook converter.
* JSON mapping structure has changed to comply to the new architecture, operators changed as well.
* `cut.py` was removed and integrated as well as a Lua filter automatically called when a `cut` operation is specified in a mapping JSON file.
* `batch.sh` was removed, as it was mostly making a bridge between `idml2docbook`, `cut.py` and Pandoc. This is not necessary anymore.

## idml-pandoc-reader 0.3.0 (2025-08-18)

* A `.design` folder and its content now exist to document the design of OutDesign.
* Started working on new Lua filters to apply mapping through Pandoc, and not Python.
* Fixed a bug where paragraph and style names extraction was raising an error if there was an extra IDML layer.

## idml-pandoc-reader 0.2.0 (2025-08-01)

* Role names are now using the same `custom_slugify` method as filenames.

## idml-pandoc-reader 0.1.0 (2025-07-31)

Initial release.