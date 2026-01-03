import subprocess
from bs4 import BeautifulSoup, NavigableString
import copy
import os
import re
import logging

from idml2hubxml import *
from utils import *
from map import *

NODES_TO_REMOVE = [
    "info",      # at some point it would be good to get those metadata and convert it.
    "sidebar",   # will need to be implemented sometime, but might be hard?
    # "link",
    # "xml-model"
    # "StoryPreference",
    # "InCopyExportOption",
    # "ACE",
    # "Properties",
]

# IDML_TO_DOCBOOK = {
#     "Story": "section"
# }

LAYERS_TO_REMOVE = [
    # "Ants"
]

ATTRIBUTES_TO_REMOVE = [
    # "idml2xml:layer", # means that it must be after the previous removals
    # "xmlns:idml2xml",
]

def remove_unnecessary_layer(soup):
    for layer in LAYERS_TO_REMOVE:
        for el in soup.find_all(attrs={"idml2xml:layer": layer}): el.decompose()

def remove_unnecessary_nodes(soup):
    for tag in NODES_TO_REMOVE:
        for el in soup.find_all(tag): el.decompose()

def remove_unnecessary_attributes(soup):
    for attr in ATTRIBUTES_TO_REMOVE:
        for el in soup.find_all(attrs={attr: True}): del el[attr]

def unwrap_unnecessary_nodes(soup):
    for tag in NODES_TO_UNWRAP:
        for el in soup.find_all(tag):
            logging.debug("Unwrapping " + tag)
            el.unwrap()

def fill_empty_elements_with_br(soup):
    """Adds a <br> tag in every empty para element.
    """
    logging.info("Removing empty elements...")
    for el in soup.find_all("para"):
        if el.is_empty_element:
            el.append(soup.new_tag("br"))

def process_images(soup, rep_raster = None, rep_vector = None, folder = None):
    logging.info("Processing media filenames...")

    for tag in soup.find_all(["mediaobject", "inlinemediaobject"]):
        imagedata = tag.find_next("imagedata")
        fileref = imagedata["fileref"]
        new_fileref = ""

        base, file_ext = os.path.splitext(fileref)
    
        # Decode the base
        base = decode_path(base)

        # Slugify the filename
        filename = base.split("/").pop()
        filename = custom_slugify(filename, 100)
        base = "/".join(base.split("/")[:-1]) + "/" + filename

        if rep_raster and (file_ext.lower() in RASTER_EXTS): new_fileref = base + "." + rep_raster
        elif rep_vector and (file_ext.lower() in VECTOR_EXTS): new_fileref = base + "." + rep_vector
        else: new_fileref = base + file_ext.lower()

        if folder: imagedata["fileref"] = folder + "/" + new_fileref.split("/").pop()
        else: imagedata["fileref"] = new_fileref

        if (rep_raster or rep_vector or folder):
            logging.debug("Media was: " + fileref)
            logging.debug("and is now: " + imagedata["fileref"])

def process_tabs(soup):
    """<tab> elements are replaced by <phrase role="[existing role] converted-tab">[tag children]</phrase>"""
    for tab in soup.find_all("tab"):
        tab.name = "phrase"
        if "role" in tab.attrs.keys(): tab["role"] += " converted-tab"
        else: tab["role"] = "converted-tab"

def process_endnotes(soup):
    """In DocBook, there is no difference between an endnote and a footnote.
    Everything is just a <footnote>. IDML distinguishes footnotes and endnotes, and Hub XML
    does as well. Here, we process footnotes regularly, and add a role="endnote" attribute
    to endnotes in order to still differentiate them.

    Input example:
    - In the text body:
      <link xml:id="id_endnoteAnchor-u8d91"
          remap="EndnoteRange"
          linkend="id_en-u8d92">7</link>

    - At the end of the document:
      [...]
      <para>
      <anchor xml:id="id_en-u8d92" role="hub:endnote"/>
          <phrase role="hub:identifier"> <link remap="EndnoteMarker" linkend="id_endnoteAnchor-u8d91">7</link></phrase>My endnote.
      </para>

    Output example, in place of the text body snippet:
    <footnote endnote="1"><para>My endnote.</para></footnote>
    """

    logging.info("Processing endnotes...")

    # Map of endnote anchors by id for quick lookup
    endnote_map = {}
    for anchor in soup.find_all("anchor", attrs={"role": "hub:endnote"}):
        anchor_id = anchor.get("xml:id")
        if not anchor_id:
            continue
        para = anchor.find_parent("para")
        if para:
            endnote_map[anchor_id] = para

    # Process all in-text endnote references
    for link in soup.find_all("link", attrs={"remap": "EndnoteRange"}):
        linkend = link.get("linkend")
        if not linkend or linkend not in endnote_map:
            logging.warning(f"Endnote target not found for linkend={linkend}")
            continue

        # Get the corresponding endnote paragraph
        endnote_para = endnote_map[linkend]

        # Deep copy the content
        note_copy = copy.copy(endnote_para)

        # remove the anchor that only marks the note location
        for el in note_copy.find_all("anchor", attrs={"role": "hub:endnote"}):
            el.decompose()
        
        # remove only the EndnoteMarker link
        for el in note_copy.find_all("link", attrs={"remap": "EndnoteMarker"}):
            el.decompose()

        note_text_content = [child for child in note_copy.contents if not (isinstance(child, NavigableString) and not child.strip())]

        # Create the <footnote> structure
        footnote_tag = soup.new_tag("footnote")
        footnote_tag["endnote"] = "1" # This acts as a marker to differiate endnotes from footnotes
        para_tag = soup.new_tag("para")

        for child in note_text_content:
            para_tag.append(copy.copy(child))

        footnote_tag.append(para_tag)

        link.replace_with(footnote_tag)

    # After all replacements, remove original endnote paras
    for para in set(endnote_map.values()):
        para.decompose()

    logging.info("Endnotes processed successfully.")


def remove_ns_attributes(soup):
    # Remove all css nodes
    for tag in soup.select('css|*'):
        tag.decompose()
    # Remove attributes
    for tag in soup.select("*"):
        to_remove = []
        for attr, _ in tag.attrs.items():
            if attr.startswith("css:") or attr.startswith("xmlns:") or attr.startswith("idml2xml:"):
                to_remove.append(attr)
        for attr in to_remove:
            del tag[attr]

def remove_linebreaks(soup):
    """When working with ragged paragraphs, some <br> tags might be added
    It can be handy to replace them with spaces to have more reflowable content."""
    logging.info("Removing linebreaks...")
    for tag in soup.select("br"):
        tag.string = " "
        tag.unwrap()

def replace_linebreaks(string):
    return string.replace("<br/>", "<simpara><?asciidoc-br?></simpara>")

def clean_urls_from_linebreaks(soup):
    """URLs can have line breaks within to compose correct rags.
    This method removes those line breaks by joining the strings that start with http and
    that are separated by a <br/> tag. The URL can't end with a line break in the source file."""
    s = str(soup)

    url_regex_with_br = r"https?:\/\/([-A-zÀ-ÿ0-9]+\.)?([-A-zÀ-ÿ0-9@:%._\+~#=]+(<br/>)?)+\.[A-zÀ-ÿ0-9()]{1,6}(\b[-A-zÀ-ÿ0-9()@:%;_\+.~#?&//=]*(<br/>)?)*"

    def replacer(match):
        return match.group(0).replace(r"<br/>", "")
    
    return BeautifulSoup(re.sub(url_regex_with_br, replacer, s), "xml")

def remove_orthotypography(soup):
    logging.info("Removing input's orthotypography...")
    s = str(soup)

    # Remove non-discretionary hyphens
    non_discretionary_hyphen = u"\u00ad"
    s = s.replace(non_discretionary_hyphen, "")

    # Replace special spaces with spaces
    special_spaces = [
    u"\u00a0", u"\u1680", u"\u180e", u"\u2000", u"\u2001", u"\u2002", u"\u2003", u"\u2004",
    u"\u2005", u"\u2006", u"\u2007", u"\u2008", u"\u2009", u"\u200a", u"\u200b", u"\u202f",
    u"\u205f", u"\u3000"
    ]

    for space in special_spaces:
        s = s.replace(space, " ")

    return BeautifulSoup(s, "xml")

def move_space_outside_of_phrase(soup, space_chars=" \u00a0\u202f"):
    for phrase in list(soup.find_all("phrase")):
        # flattened text inside the phrase
        total_text = phrase.get_text()
        if total_text.strip(space_chars) == "":
            # If the phrase is only spaces, we unwrap it.
            # Not sure if this is good in all cases, but it made sense
            # at least in one real-life case.
            phrase.unwrap()
            continue

        # operate on first descendant text node for leading spaces
        descendant_strings = [s for s in phrase.find_all(string=True)]
        if descendant_strings:
            first = descendant_strings[0]
            first_text = str(first)
            leading = len(first_text) - len(first_text.lstrip(space_chars))
            if leading:
                logging.debug("Leading space(s) found a <phrase> element, moved before: " + str(phrase))
                lead_spaces = first_text[:leading]
                new_first = first_text[leading:]
                first.replace_with(soup.new_string(new_first))
                phrase.insert_before(soup.new_string(lead_spaces))

        # re-evaluate descendant strings and operate on the last node for trailing
        descendant_strings = [s for s in phrase.find_all(string=True)]
        if descendant_strings:
            last = descendant_strings[-1]
            last_text = str(last)
            trailing = len(last_text) - len(last_text.rstrip(space_chars))
            if trailing:
                logging.debug("Trailing space(s) found a <phrase> element, moved after: " + str(phrase))
                trail_spaces = last_text[-trailing:]
                new_last = last_text[:-trailing] if trailing < len(last_text) else ""
                last.replace_with(soup.new_string(new_last))
                phrase.insert_after(soup.new_string(trail_spaces))

    return soup

def add_french_orthotypography(soup, thin_spaces):
    """Applies a series of regex to comply to French orthotypography rules
    if thin_spaces, it only uses non-breaking thin spaces.
    """
    logging.info("Adding new french orthotypography...")

    s = str(soup)

    s = re.sub(r"\s([!\?;€\$%])", u"\u202f" + r'\1', s) # thin spaces
    s = re.sub(r"\s\:", (u"\u202f" if thin_spaces else u"\u00a0") + r':', s) # nbsp, doesn't seem to work...
    s = re.sub(r"(\d)\s(\d\d\d)", r'\1' + u"\u202f" + r'\2', s) # numbers
    s = re.sub(r"«\s?", r'«' + u"\u202f", s) # quotes
    s = re.sub(r"\s?»", u"\u202f" + r'»', s) # quotes
    s = re.sub(r"([^0-9])°\s?", r'\1°' + u"\u202f", s) # degrees
    s = re.sub(r"\.\.\.", r'…', s) # suspension marks

    return BeautifulSoup(s, "xml")

def hubxml2docbook(file, **options):
    logging.info("hubxml2docbook starting...")
    # Read the HTML input file
    with open(file, "r") as f:
        xml_content = f.read()

    logging.info(file + " read succesfully!")

    soup = BeautifulSoup(xml_content, "xml")

    # This line fixes the roles names
    # If your map file was designed using v0.1.0, comment it
    fix_role_names(soup)

    for hub in soup.find_all("hub"):
        hub.name = "article"
        hub["version"] = "5.0"
    for tag in soup.find_all(string=lambda text: isinstance(text, str) and text.strip().startswith("xml-model")):
        tag.extract()
    # <article version="5.0" xml:lang="fr-FR" xmlns="http://docbook.org/ns/docbook">

    if not options["ignore_overrides"]: soup, _, _ = turn_overrides_into_roles(str(soup))

    remove_unnecessary_nodes(soup)
    # remove_unnecessary_layer(soup)
    remove_unnecessary_attributes(soup)
    remove_ns_attributes(soup)

    process_images(soup,
        options["raster"],
        options["vector"],
        options["media"])

    process_tabs(soup)

    process_endnotes(soup)

    soup = clean_urls_from_linebreaks(soup) # must be done before remove_linebreaks and removeHyphens

    if not options["linebreaks"]: remove_linebreaks(soup)

    fill_empty_elements_with_br(soup)

    soup = remove_hyphens(soup, "xml")

    if options["typography"]:
        soup = remove_orthotypography(soup)
        soup = add_french_orthotypography(soup, options["thin_spaces"])
        soup = move_space_outside_of_phrase(soup)

    if options["prettify"]:
        logging.warning("Prettifying can result in errors depending on whatcha wanna do afterwards!")
        docbook = soup.prettify()
        # prettify adds `\n` around inline elements,
        # which is parsed as spaces in Pandoc.
        # str(soup) does it less, but to ensure we don't have
        # this problem, we just remove linebreaks entirely.
    else:
        docbook = str(soup).replace("\n", "")

    docbook = replace_linebreaks(docbook)

    logging.info("hubxml2docbook done.")

    return docbook

def idml2docbook(input, **options):
    logging.info("idml2docbook starting...")
    if options["idml2hubxml_file"]:
        hubxml = input
        logging.warning("Directly reading the input as a hubxml file.")
    else:
        hubxml = idml2hubxml(input, **options)
    docbook = hubxml2docbook(hubxml, **options)
    logging.info("idml2docbook done.")
    return docbook