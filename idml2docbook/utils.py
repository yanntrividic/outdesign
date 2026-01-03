from bs4 import BeautifulSoup, Tag
import re
import unidecode
import json
import sys
import urllib
import os

# InDesign leaves hyphens from the INDD file in the HTML export
# Hopefully, it leaves them with a trailing space,
# which allows us to spot them easily with a regular expression.
def remove_hyphens(soup, parser):
    return BeautifulSoup(re.sub(r'([a-zA-ZÀ-Ÿ])\-\s([a-zA-ZÀ-Ÿ])', r'\1\2', str(soup)), parser)

# Pandoc's AST takes into account all spans,
# even if they don't carry any useful information
# this allows to clean the document before sending
# it to Pandoc.
def unwrap_superfluous_spans(soup):
    for s in soup.find_all('span'):
        if not s.attrs:
            s.unwrap()

def remove_empty_lines(soup, parser):
    # There might be a few empty lines laying around:
    return BeautifulSoup(re.sub(r"\n+", r"\n", str(soup)), parser)


# Former slugs.py file

def custom_slugify(string, length=5):
    regex_subs = [
        (r"[’°:;,\(\)\*]", " "), # replaces punctuation with spaces
        (r"[^\w\s-]", ""),  # remove non-alphabetical/whitespace/'-' chars
        (r"(?u)\A\s*", ""),  # strip leading whitespace
        (r"(?u)\s*\Z", ""),  # strip trailing whitespace
        (r"[-\s_]+", "_"),  # reduce multiple whitespace or '-' to single '_'
    ]
    full_slug = slugify(string, regex_subs, preserve_case=True, use_unicode=True)
    return "_".join(full_slug.split("_")[:length])

def slugify(value, regex_subs=(), preserve_case=False, use_unicode=False):
    """
    Normalizes string, converts to lowercase, removes non-alpha characters,
    and converts spaces to hyphens.

    Took from Pelican sources.

    For a set of sensible default regex substitutions to pass to regex_subs
    look into pelican.settings.DEFAULT_CONFIG['SLUG_REGEX_SUBSTITUTIONS'].
    """

    import unicodedata
    import unidecode

    def normalize_unicode(text):
        # normalize text by compatibility composition
        # see: https://en.wikipedia.org/wiki/Unicode_equivalence
        return unicodedata.normalize("NFD", text)

    # normalization
    value = normalize_unicode(value)

    if not use_unicode:
        # ASCII-fy
        value = unidecode.unidecode(value)

    # perform regex substitutions
    for src, dst in regex_subs:
        value = re.sub(
            normalize_unicode(src), normalize_unicode(dst), value, flags=re.IGNORECASE
        )

    if not preserve_case:
        value = value.lower()

    return value.strip()

def decode_path(encoded_path):
    """In IDML, paths are encoded as URLs.
    It is sometimes necessary to decode them."""
    return urllib.parse.unquote(encoded_path)

def generate_xml_id(title_text, xml_ids):
    xml_id = custom_slugify(title_text)
    if xml_id in xml_ids:
        count = sum(xml_id in s for s in xml_ids)
        xml_id = xml_id + "_" + str(count + 1)
    xml_ids.append(xml_id)
    return xml_id