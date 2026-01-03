import re
import sys
import json
import logging
import os
from utils import custom_slugify
from bs4 import BeautifulSoup
from natsort import natsorted
import natsort as ns
import pandas as pd

APPLY_HEURISTICS = True

BOLD = '\033[1m'
END = '\033[0m'
OKGREEN = '\033[92m'
WARNING = '\033[93m'

BASE_PREFIX_CHARACTER_STYLE = 'override-character-style-'
BASE_PREFIX_PARAGRAPH_STYLE = 'override-paragraph-style-'

# Those two lists need some tests and adjustments...
TAGS_WITH_CSSA = [
    "article",
    "para",
    "phrase",
    "sidebar",
    "tab",
    "mediaobject",
    "inlinemediaobject",
    "informaltable",
    "imagedata",
    "superscript",
    "sidebar",
    "entry",
    "link"
]

TAGS_WITH_RELEVENT_ROLES = [
    "para",
    "phrase",
    "mediaobject",
    "inlinemediaobject",
    "superscript",
]

def get_map(file):
    logging.info("Reading map file at: " + file)
    f = open(file)
    # returns JSON object as a list 
    data = None
    try:
        data = json.load(f)
        logging.debug("Data read from map file: " + str(data))
    except:
        logging.warning("No data was read from map file.")
    return data

def log_map_entry(entry):
    s = ""
    if "type" in entry: s = s + entry.get("type")
    if "classes" in entry: s = s + ("." + entry.get("classes") if entry.get("classes") else "" )
    if "level" in entry: s = s + " [level " + str(entry.get("level")) + "]"
    if "simplify" in entry: s = s + "[simplified!]"
    if "empty" in entry: s = s + "[empty kept]"
    if "br" in entry: s = s + "[linebreak inserted]"
    if "wrap" in entry: s = s + "[in " + str(entry.get("wrap")) + "]"
    if "attrs" in entry: s = s + "[attrs added " + str(entry.get("attrs")) + "]"
    if "delete" in entry: return "deleted!"
    if "unwrap" in entry: return "unwrapped!"
    if s == "": return "no operation applied!"
    return s

def bold_print(s):
    print(BOLD + s + END)

def build_roles_map(soup):
    """Takes a Hub XML soup as input, and builds a dict
    containing the exact InDesign style, the Hub role name,
    if the style is a default one, and a slugified role name as key."""
    roles = {}
    for rule in soup.find_all("css:rule"):
        if "native-name" in rule.attrs:
            to_slugify = native = rule.attrs["native-name"]
            default = False
            
            if native.startswith("$ID/"):
                default = True
                to_slugify = native[4:]
            slug = custom_slugify(to_slugify)

            roles[slug] = {"hub": rule.attrs["name"], "native": native, "default": default}
    return roles

def update_roles_with_better_slugs(soup, roles):
    """Takes a Hub XML soup and the corresponding roles
    map, and updates the roles."""
    for key, value in roles.items():
        log = False
        for property in ["role", "name"]:
            for el in soup.find_all(attrs={property: value["hub"]}):
                if el[property] != key:
                    el[property] = key
                    if not log:
                        logging.debug("Role name for style \"" + value["native"] + "\" was changed: " + value["hub"] + " -> " + key)
                        log = True


def normalize_attr_name(name: str) -> str:
    """Return the local name with any namespace/prefix removed."""
    if name.startswith('css_namespace__'):
        name = name[len('css_namespace__'):]
    return name

def looks_like_css_attr(name: str):
    """
    Heuristic: detect attributes that were intended as css:*,
    which means attributes that start with the css_namespace__ prefix
    """
    if name.startswith('css_namespace__'):
        return True
    return False

def canonical_css_key(tag, include_role=True):
    """Create a stable tuple key of (localname, value) sorted by name/value."""
    items = []
    relevant_properties = ["remap", "native-name", "name"]
    if include_role: relevant_properties += ["role"]
    for k, v in list(tag.attrs.items()):
        if looks_like_css_attr(k) or k in relevant_properties : items = filter_property(items, tag, k, v)
    items.sort()
    return tuple(items)

# Some CSS properties are not relevant here, so we might want to
# filter them in order to have more interesting overrides classes...
def filter_property(items, tag, k, v, apply_heuristics=APPLY_HEURISTICS):
    # Some CSSa (https://github.com/le-tex/CSSa) properties 
    # must be deleted for a smarter overrides detection. 
    # This list needs to be refined.
    CSSA_PROPERTIES_TO_IGNORE = [
        "hyphens",                 # usually used for handling rags
        "initial-letter",          # ignoring drop caps
        "letter-spacing",          # usually used for handling rags
        "line-height",             # maybe we can ignore it as well?
        "text-decoration-offset",  # offset with the underlines
        "text-decoration-width",   # width of the underline
        "break-after",             # is this added by idml2hubxml to avoid the block-break character?
        "page-break-after",        # is this added by idml2hubxml to avoid the page-break character?
        "border-width",            # applied on chars by idml2hubxml, but seems to be a bug.
        "margin-top",              # often used to adjust in the page.
        "margin-bottom",           # often used to adjust in the page.
        "direction",               # reading direction, most certainly is not relevent there...
        "text-align-last",         # a wild guess...
    ]

    name = normalize_attr_name(k)
    append = True

    if apply_heuristics:
        # If we ignore this property, pass
        if name in CSSA_PROPERTIES_TO_IGNORE:
            del tag[k]
            append = False
        # If the color is equivalent to the default color or if is black transparent, pass
        if v == "device-cmyk(0,0,0,1)": append = False
        if v == "device-cmyk(0,0,0,0)": append = False
        # TODO: Detect if value is 0 or one of the variants, and append false
    
    if append: items.append((name, v))

    return items

def turn_overrides_into_roles(xml):
    # Hacky way to enable namespace support for the `css:`-prefixed attributes
    xml = xml.replace('css:', 'css_namespace__')

    soup = BeautifulSoup(xml, "xml")

    para_map = {}      # properties_tuple -> index
    para_applied = {}  # properties_tuple -> set(base_role)
    paragraph_styles_overrides = []     # list of (index, applied_to_set, properties_tuple) in index order

    char_map = {}
    char_applied = {}
    character_styles_overrides = []

    obj_map = {}
    obj_applied = {}
    object_styles_overrides = []

    # Stable counters per type (1-based)
    counters = {"paragraph": 0, "character": 0, "object": 0}

    # Walk only para and phrase
    for tag in soup.find_all(TAGS_WITH_CSSA):
        # find css-like attrs
        css_items = [(k, v) for k, v in tag.attrs.items() if looks_like_css_attr(k)]
        if not css_items:
            continue

        key = canonical_css_key(tag, False)  # tuple of (cssa-property, value)
        if not key: continue

        if tag.name == 'para':
            type_name = "paragraph"
            mapping = para_map
            applied = para_applied
            out_list = paragraph_styles_overrides
        elif tag.name in ["phrase", "superscript"]:
            type_name = "character"
            mapping = char_map
            applied = char_applied
            out_list = character_styles_overrides
        elif tag.name in TAGS_WITH_RELEVENT_ROLES: # could be informaltable, mediaobject, 
              # sidebar, tab, inlinemediaobject, sidebar, entry, link...
              # we will need to handle them at some point!
            type_name = "object"
            mapping = obj_map
            applied = obj_applied
            out_list = object_styles_overrides

        if tag.name in TAGS_WITH_RELEVENT_ROLES:
            if key not in mapping:
                counters[type_name] += 1
                idx = counters[type_name]
                mapping[key] = idx
                applied[key] = set()
                out_list.append((idx, applied[key], key))
            else:
                idx = mapping[key]

            # record base role if present
            base_role = tag.get('role')
            if base_role:
                applied[key].add(base_role)

            # update or create role
            override_label = f"{type_name}-override-{idx}"
            current_role = tag.get('role')
            new_role = current_role + " " + override_label if current_role else override_label
            tag["role"] = new_role

        # remove the detected css-like attributes from the element
        for k, _ in css_items:
            if k in tag.attrs:
                del tag[k]

    return soup, paragraph_styles_overrides, character_styles_overrides

def get_styles(xml):

    soup = BeautifulSoup(xml, "xml")

    paragraph_styles = {}
    character_styles = {}

    for tag in soup.find_all("css_namespace__rule"):
        
        key = canonical_css_key(tag)

        if tag.attrs["layout-type"] == "para": paragraph_styles[tag.attrs["name"]] = key
        if tag.attrs["layout-type"] == "inline": character_styles[tag.attrs["name"]] = key
    
    return paragraph_styles, character_styles

def generate_ods(
    paragraph_styles,
    character_styles,
    paragraph_styles_overrides,
    character_styles_overrides,
    filename_stem):

    output_file = f"{filename_stem}.ods"

    pairs = [
        ("paragraph", paragraph_styles, False),
        ("character", character_styles, False),
        ("paragraph", paragraph_styles_overrides, True),
        ("character", character_styles_overrides, True)
    ]

    # TODO: If at some point we want a better looking output
    # https://xlsxwriter.readthedocs.io/working_with_pandas.html
    with pd.ExcelWriter(output_file) as writer:  
        for label, styles, is_override in pairs:
            rows = []

            if is_override:
                for idx, applied_to, key in styles:
                    row = {kk: vv for kk, vv in key}  # flatten canonical key tuple
                    row["role"] = f"{label}-override-{idx}"
                    if applied_to:
                        row["applied_to"] = ", ".join(sorted(applied_to))
                    else:
                        row["applied_to"] = ""
                    rows.append(row)
            else:
                for name, key in styles.items():
                    row = {kk: vv for kk, vv in key}
                    row["name"] = name
                    rows.append(row)

            if not rows:
                continue  # skip empty sheets

            df = pd.DataFrame(rows)
            
            # reorder columns
            cols = df.columns.tolist()

            # Ensure 'role', 'base_role', and 'override_num' are first
            ordered = []
            for col in ["name", "role", "applied_to", "native-name", "remap"]:
                if col in cols:
                    ordered.append(col)
                    cols.remove(col)
            cols = ordered + natsorted(cols, alg=ns.IGNORECASE)
            df = df[cols]

            sheet_name = label + ("_overrides" if is_override else "")
            df.to_excel(writer, index=False, engine="ods", sheet_name=sheet_name)

    print(f"✅ Saved styles and overrides to {output_file}")

def generate_css(
    paragraph_styles,
    character_styles,
    paragraph_styles_overrides,
    character_styles_overrides,
    filename_stem):
    """In the same way generate_ods generates an ODS file with styles and overrides,
    generate_css generates a CSS file with all the styles, overrides and properties from
    the input file."""

    output_file = f"{filename_stem}.css"

    def format_css_block(selector, props):
        IGNORED_PROPS = ["name", "native-name"]
        lines = [f"{selector} {{"]
        props["--element"] = "\"" + selector + "\""
        for k, v in props.items():
            print(v, type(v))
            if k not in IGNORED_PROPS:
                if k == "font-family": v = "\"" + v + "\""
                lines.append(f"  {k}: {v};")
        lines.append("}\n")
        return "\n".join(lines)

    with open(output_file, "w", encoding="utf-8") as out:
        out.write("/* Auto-generated CSS from IDML converter */\n\n")

        sections = [
            ("Paragraph styles", paragraph_styles, False),
            ("Character styles", character_styles, False),
            ("Paragraph styles overrides", paragraph_styles_overrides, True),
            ("Character styles overrides", character_styles_overrides, True),
        ]

        for label, styles, is_override in sections:
            if not styles:
                continue

            out.write(f"/* {label} */\n")

            if is_override:
                for idx, applied_to, key in styles:
                    props = {kk: vv for kk, vv in key}
                    selector = f".{label.lower().replace(' ', '-')}-{idx}"
                    out.write(format_css_block(selector, props))
            else:
                for name, key in styles.items():
                    props = {kk: vv for kk, vv in key}
                    selector = f".{name}"
                    out.write(format_css_block(selector, props))

    print(f"✅ Saved CSS to {output_file}")

def generate_json_template(roles, file):
    selectors = set()
    for role, tag in roles:
        if tag not in TAGS_WITH_RELEVENT_ROLES:
            continue
        classes = role.split()
        selector = "." + ".".join(classes)
        selectors.add(selector)

    selectors = natsorted(selectors, alg=ns.IGNORECASE)

    json_template = [{"selector": s, "operation": {}} for s in selectors]

    file_stem = os.path.splitext(file)[0]
    template_filename = f"{file_stem}_template.json"

    with open(template_filename, "w", encoding="utf-8") as out:
        out.write("[\n")
        for i, entry in enumerate(json_template):
            comma = "," if i < len(json_template) - 1 else ""
            out.write(f'    {{ "selector": "{entry["selector"]}", "operation": {{}} }}{comma}\n')
        out.write("]\n")

    print(f"\n✅ JSON template saved to {template_filename}")
    sys.exit(0)

def fix_role_names(soup):
    roles = build_roles_map(soup)
    update_roles_with_better_slugs(soup, roles)

def build_dict_from_map_array(map):
    map_dict = {}
    for entry in map:
        map_dict[entry["selector"][1:].replace(".", " ")] = entry["operation"]
    return map_dict

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: python map.py input.xml map.json [--to-ods] [--to-css] [--to-json-template]")
        sys.exit(1)

    to_ods = "--to-ods" in sys.argv
    to_css = "--to-css" in sys.argv
    to_json_template = "--to-json-template" in sys.argv

    sys.argv = [arg for arg in sys.argv if arg not in ["--to-ods", "--to-css", "--to-json-template"]]

    file = sys.argv[1]
    map_file = sys.argv[2]

    file = sys.argv[1]
    map = get_map(sys.argv[2])
    map = build_dict_from_map_array(map)

    # Read the HTML input
    with open(file, "r") as f:
        hubxml = f.read()

    soup = BeautifulSoup(hubxml, "xml")
    fix_role_names(soup)
    hubxml = str(soup)
    hubxml = hubxml.replace('css:', 'css_namespace__')
    paragraph_styles, character_styles = get_styles(hubxml)
    soup, paragraph_styles_overrides, character_styles_overrides = turn_overrides_into_roles(hubxml)
    hubxml = str(soup)

    # Save as ODS
    if to_ods:
        file_stem = os.path.splitext(file)[0]
        generate_ods(
            paragraph_styles,
            character_styles,
            paragraph_styles_overrides,
            character_styles_overrides,
            file_stem
        )

    # Save as CSS
    if to_css:
        file_stem = os.path.splitext(file)[0]
        generate_css(
            paragraph_styles,
            character_styles,
            paragraph_styles_overrides,
            character_styles_overrides,
            file_stem
        )

    type_and_role = r'<(\w+)[^>]*\brole="(.*?)"[^>]*>'

    roles = set()

    try:
        for tag_name, role_attr in re.findall(type_and_role, hubxml.split("</info>")[1]):
            if not role_attr.startswith("hub"):
                roles.add((role_attr, tag_name))
    except Exception as e:
        raise ValueError("This file doesn't seem to be coming from idml2xml...") from e

    bold_print("Role/tag couples present in " + file + ":")
    for role, tag in natsorted(roles, alg=ns.IGNORECASE):
        if tag in TAGS_WITH_RELEVENT_ROLES:
            print(f"- {role} ({tag})")

    if to_json_template: generate_json_template(roles, file)

    map = get_map(map_file)
    map = build_dict_from_map_array(map) if map else {}

    covered = []
    uncovered = []

    for role, tag in natsorted(roles, alg=ns.IGNORECASE):
        if tag in TAGS_WITH_RELEVENT_ROLES:
            if map and role not in map:
                uncovered.append((role, tag))
            elif map:
                covered.append(role)

    uncovered.sort(key=lambda c: 1 if c[1] == "phrase" else 0)
    covered.sort(key=lambda c: 1 if c[1] == "phrase" else 0)

    if map:
        print(OKGREEN)
        if covered:
            bold_print("Applied mapping:")
            for c in covered:
                print("- " + c + " => " + log_map_entry(map[c]))
        else:
            bold_print(WARNING + (map_file + " does not apply to " + file))

        if uncovered:
            print(WARNING)
            bold_print("Unhandled elements:")
            for c in uncovered:
                print(f"- {c[0]} ({c[1]})")
        else:
            print(OKGREEN + "All elements are covered!")
        print(END)
    else:
        print("\nNo data was read from the map file!")
