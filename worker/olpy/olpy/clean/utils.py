import numpy as np
import pandas as pd
import hashlib


def stringify(item, onblank = ''):
    if not item or item != item:
        return onblank
    return str(item)


def try_to_process(item, funs_to_try = [lambda x: x]):
    '''
    Tries a sequence of functions on an item, returning the first successful call.
    Shamelessly EAFP.
    '''

    exceptions = []
    for fun in funs_to_try:
        try:
            return fun(item)
        except Exception as exc:
            exceptions.append(str(exc))
    print(f'Processing {item} failed.')
    print(f'Error messages: {exceptions}')



def hash_together(values, salt = ""):
    """
    Concatenates a list of strings with salt and returns the sha256 hash in hex

    If strings are all blank, None, or NaN, an empty string is returned.
    This is because a primary key generated from such a list should be blank
    in order to indicate no entity should be created.
    """

    substance = "".join([str(s).strip() for s in values if s == s and s is not None])
    if substance == "":
        return ""
    return hashlib.sha256((substance + salt).encode('utf-8')).hexdigest()

def hash_row_columns(row, columns = [], salt = ""):
    strings_to_hash = [row[c] for c in columns]
    return hash_together(values = strings_to_hash, salt = salt)

def hash_df_columns(df, columns = [], salt = ""):
    return df.apply(lambda x: hash_together(values = [x[c] for c in columns], salt = salt), axis=1)

def parse_name(name, comma=True, ignore_comma=False):
    """
    Parses a name with the following procedure:

    - By default, if there is a comma in the string, the string is split on the comma and reversed
    - comma=False can be passed to the function if you expect there to be no commas
    - If a comma is found with comma=False this will raise a ValueError, unless you set ignore_comma=True 
    - String is split into a list of words. Words are converted to lower case and special chars are removed
    - Multiword names are converted into joined strings
    - Suffixes are parsed out
    - Firstname is the first element of reordered string, lastname is the last element, middlename is everything in between
    - All Names are converted to title case
    """
    if comma == True:
        name = " ".join(name.split(",")[::-1])
    elif comma == False and "," in name:
        if ignore_comma == False:
            raise ValueError('Unhandled comma in name parsing.. Do you want to set comma=True in parse_name??')
    words = name.split(" ")
    name_series = pd.Series()
    for word in words:
        word = word.strip()
        word_position = words.index(word)
        if word == '':
            words.pop(word_position)
        lower_case_no_special_chars = ''.join(e.lower() for e in word if e.isalnum())
        if lower_case_no_special_chars in ['de', 'van']:
            multi_word_name = " ".join(words[words.index(word):words.index(word)+2])
            words.pop(word_position)
            words.pop(word_position)
            words.insert(word_position, multi_word_name)
        if lower_case_no_special_chars in ['jr', 'iii', 'ii', 'sr']:
            name_series['suffix'] = lower_case_no_special_chars.title()
            words.pop(word_position)
        else:
            name_series['suffix'] = ''
        name_series['firstname'] = words[0].title()
        name_series['middlename'] = " ".join(words[1:len(words)-1]).title()
        name_series['lastname'] = words[len(words)-1].title()
        
    return name_series

def decapitated(df, shorten_names = False):
    """
    Returns a decapitated pandas dataframe.
    """

    new_header = df.iloc[0] #grab the first row for the header
    out = df[1:] #take the data minus the header row
    out.columns = new_header #set the header row as the df header
    if (shorten_names):
        out.columns = out.columns.map(shorten_to_63_chars)
    return out

def shorten_to_63_chars(string):
    """
    Trims the middle out of a string until it's <= 63 characters.
    
    Useful because postgres limits column names to 63 chars.
    """

    string = str(string)
    if len(string) > 63:
        out =  '%s...%s'%(string[:30], string[-30:])
        print(out)
        return out
    return string


def cut_lines_to_n(string, n = 200):
    """
    Takes a string and breaks it into lines with <= n characters per line.

    Useful because psql queries have to have < 212 chars per line.
    """

    out = []
    lines = string.split("\n")
    for line in lines:
        newline = ""
        words = line.split(" ")
        for word in words:
            if len(newline + word) + 1 > n:
                out.append(newline.strip())
                newline = word
            else:
                newline += " " + word
        out.append(newline)
    return "\n".join(out)


def unnest(df):
    """
    Runs df.explode(*) on all columns
    """

    oper = df
    for col in df.columns:
        oper = oper.explode(col)
    return oper


def ensure_hashable(df):
    """
    A more compact version of unnest
    Multi-valued lists will be converted into
    frozensets.
    """

    def try_collapse(value):
        if isinstance(value, list):
            if len(value) == 1:
                return value[0]
            if len(value) == 0:
                return np.nan
            return frozenset(value)
        return value
    return df.applymap(try_collapse)