from __future__ import division
from datetime import datetime, timedelta, date
from butterfingers import butterfingers
from collections import Counter
import scipy.stats as stats
import pandas as pd
import numpy as np
import random
import string
import names
import uuid
import copy
import sys
import re
import os

class FirstName(object):
    '''
    class to generate, store and introduce errors in first names
    introduced errors: typo
    '''
    def __init__(self, gender=None):
        self.generate(gender=gender)
    def generate(self, gender=None):
        self.name = names.get_first_name(gender = gender)
        return self
    def introduce_typo(self,prob,firstname):
        variant = introduce_typos_string(firstname,prob)
        return variant
    def get_nickname(self,prob,firstname):
        curpath = os.path.dirname(__file__)
        # nicknames distributed as public domain:
        # https://danconnor.com/posts/4f65ea41daac4ed03100000f/csv_database_of_common_nicknames
        nickfile = os.path.join(curpath,'media/nicknames.csv')
        nicknames = pd.read_csv(nickfile,skipinitialspace=True)
        variant = firstname
        if np.random.binomial(1,prob):
            existsmain = np.where(nicknames.name.isin([firstname]))[0]
            if len(existsmain)>0:
                variant = np.random.choice(nicknames.nickname[existsmain])
            existsnick = np.where(nicknames.nickname.isin([firstname]))[0]
            if len(existsnick)>0:
                mainname = list(nicknames.name[existsnick])
                whichmain = np.where(nicknames.name.isin(mainname))[0]
                variant = np.random.choice(nicknames.nickname[whichmain])
        return variant
    def create_variant(self,typo_prob = 0.05, nickname_prob=0, firstletter_prob = 0, **kwargs):
        variant = self.get_nickname(prob = nickname_prob,firstname=self.name)
        variant = self.introduce_typo(prob = typo_prob,firstname=variant)
        self.variant = variant
        if np.random.binomial(1,firstletter_prob):
            self.variant = variant[0]
        return self

class MiddleName(object):
    '''
    class to generate, store and introduce errors in first names
    introduced errors: typo
    '''
    def __init__(self, gender=None):
        self.generate(gender = gender)
    def generate(self, gender=None):
        self.name = names.get_first_name(gender = gender)
        return self
    def introduce_typo(self,prob,middlename):
        variant = introduce_typos_string(middlename,prob)
        return variant
    def get_nickname(self,prob,middlename):
        curpath = os.path.dirname(__file__)
        # nicknames distributed as public domain:
        # https://danconnor.com/posts/4f65ea41daac4ed03100000f/csv_database_of_common_nicknames
        nickfile = os.path.join(curpath,'media/nicknames.csv')
        nicknames = pd.read_csv(nickfile,skipinitialspace=True)
        variant = middlename
        if np.random.binomial(1,prob):
            existsmain = np.where(nicknames.name.isin([middlename]))[0]
            if len(existsmain)>0:
                variant = np.random.choice(nicknames.nickname[existsmain])
            existsnick = np.where(nicknames.nickname.isin([middlename]))[0]
            if len(existsnick)>0:
                mainname = list(nicknames.name[existsnick])
                whichmain = np.where(nicknames.name.isin(mainname))[0]
                variant = np.random.choice(nicknames.nickname[whichmain])
        return variant
    def create_variant(self,typo_prob = 0.05, nickname_prob=0, firstletter_prob = 0, **kwargs):
        variant = self.get_nickname(nickname_prob,middlename=self.name)
        variant = self.introduce_typo(prob = typo_prob,middlename=variant)
        self.variant = variant
        # get first letter with probability
        if np.random.binomial(1,firstletter_prob):
            self.variant = variant[0]
        return self

class LastName(object):
    '''
    class to generate, store and introduce errors in last names
    introduced errors: typo
    '''
    def __init__(self):
        self.generate()
    def generate(self):
        self.name = names.get_last_name()
        self.spouse = np.random.choice([self.name,names.get_last_name()],p=[0.8,0.2])
        return self
    def introduce_typo(self,prob,lastname):
        variant = introduce_typos_string(lastname,prob)
        return variant
    def create_variant(self, typo_prob = 0.05, firstletter_prob = 0, **kwargs):
        self.variant = self.spouse
        self.variant = self.introduce_typo(prob = typo_prob,lastname=self.variant)
        if np.random.binomial(1,firstletter_prob):
            self.variant = self.variant[0]
        return self

class Sex(object):
    '''
    class to generate, store and introduce errors in sex
    introduced errors: wrong choice, typo
    '''
    def __init__(self):
        self.generate()
    def generate(self):
        self.name = random.choice(['M','F'])
    def introduce_typo(self,prob,sex):
        if np.random.binomial(1,1-prob):
            return sex
        else:
            return random.choice(string.ascii_uppercase)
    def introduce_choice_er(self,prob,sex):
        ops = ['M','F']
        if np.random.binomial(1,1-prob):
            return sex
        else:
            return np.random.choice([x for x in ops if not x==sex])
    def create_variant(self,typo_prob=0.05,choice_prob=0.05,**kwargs):
        variant = self.introduce_choice_er(prob = choice_prob,sex=self.name)
        variant = self.introduce_typo(prob = typo_prob,sex=variant)
        self.variant = variant
        return self

class Ssn(object):
    '''
    class to generate, store and introduce errors in social security numbers
    introduced errors: typo
    '''
    def __init__(self):
        self.generate()
        self.name = self.stringify()
    def generate(self):
        ''' generator '''
        nums = np.random.randint(low=0,high=9,size=9)
        self.ssn_list = list(nums)
        return self
    def stringify(self,ssnlist=None):
        ''' turn ssn into string '''
        if ssnlist is None:
            ssnlist = self.ssn_list
        ar = "".join([str(x) for x in ssnlist])
        ssn = '-'.join([ar[:3],ar[3:5],ar[5:]])
        return ssn
    def introduce_typo(self,prob,ssn):
        ''' function to introduce errors into a ssn (number format) '''
        # mutate numbers
        newssn = [x if np.random.binomial(1,1-prob) \
            else random.randint(0,9) for x in ssn]
        variant = self.stringify(newssn)
        return variant
    def create_variant(self,typo_prob = 0.01, **kwargs):
        ''' creates a variant '''
        self.variant = self.introduce_typo(prob = typo_prob,ssn=self.ssn_list)
        return self

class Dob(object):
    '''
    class to generate, store and introduce errors in dates of birth
    introduced errors: typo (can be impossible date)
    '''
    def __init__(self):
        self.generate()
        self.name = self.stringify()
    def generate(self):
        ''' generator (stores in dt format) '''
        lower, upper = 365*5, 365*100
        mu,sigma = 45*365, 30*365
        X = stats.truncnorm((lower-mu)/sigma,(upper-mu)/sigma,loc=mu,scale=sigma)
        self.dobdt = datetime.now()-timedelta(days=int(X.rvs(1)))
        return self
    def stringify(self,dobdt=None):
        ''' makes string from dt format '''
        if dobdt is None:
            dobdt = self.dobdt
        dob = datetime.strftime(dobdt,'%Y-%m-%d')
        return dob
    def introduce_typo(self,prob):
        ''' introduces typos (number replacements) '''
        newdobdt = self.dobdt
        #mutate nums
        if self.dobdt.day<=12:
            if np.random.binomial(1,prob):
                newdobdt = date(self.dobdt.year,self.dobdt.day,self.dobdt.month)
        # include typo's
        curdif = datetime.now()-self.dobdt
        newyear = newdobdt.year
        newmonth = newdobdt.month
        newday = newdobdt.day
        # yearchange: days in month
        durs = {31:[1,3,5,7,8,10,12],
        30:[4,6,9,11],
        28:[2]}
        if np.random.binomial(1,prob):
            changeyear = np.round(stats.truncnorm(-curdif.days/365,10,0,3).rvs(1))
            newyear = int(newdobdt.year + changeyear)
        if np.random.binomial(1,prob):
            newmonth = int(np.random.randint(1,12))
        if np.random.binomial(1,prob):
            newday = int(np.random.randint(1,31))
        daysinmonth = [k for k,v in durs.items() if newmonth in v][0]
        newday = int(min(daysinmonth,newday))
        newdate = date(newyear,newmonth,newday)
        newdobstr = self.stringify(newdate)
        return newdobstr
    def create_variant(self, typo_prob = 0.05, **kwargs):
        ''' creates a variant '''
        self.variant = self.introduce_typo(prob = typo_prob)
        return self

class Race(object):
    '''
    class to generate, store and introduce errors in race
    introduced errors: typo
    '''
    def __init__(self):
        self.generate()
    def generate(self):
        ''' generator '''
        totalpop = 328915700
        probs = {
            'White':            223553265,
            'Black':             38929319,
            'Native American':    2932248,
            'Asian':             14674252,
            'Pacific Islander':    540013,
            'Other':             19107368,
            'Multiracial':        9009073
        }
        annotated = np.sum(list(probs.values()))
        probs['Unknown'] = (totalpop - annotated)/2
        probs['Declined'] = (totalpop - annotated)/2

        choose = np.random.choice(list(probs.keys()),
                 p=np.array(list(probs.values()))/np.sum(np.array(list(probs.values()))))
        self.name = choose
        return self
    def introduce_synonyms(self,prob,race):
        ''' introduces often used synonyms '''
        syns = {
            'White': [],
            'Black': [],
            "Asian": [],
            'Native American': ['amindian'],
            'Pacific Islander': ['pacisland'],
            'Multiracial': [],
            'Declined': [],
            "Unknown": [],
            "Other": []
        }
        if np.random.binomial(1,prob):
            if len(syns[race])>0:
                return str(np.random.choice(syns[race]))
        return race
    def introduce_typos(self,prob,race):
        ''' introduce typos '''
        variant = introduce_typos_string(race)
        return variant
    def introduce_choice_ers(self,prob,race):
        ''' introduce wrong choice '''
        if np.random.binomial(1,1-prob):
            return race
        else:
            ops = ['White', 'Black', 'Native American', 'Asian', 'Pacific Islander', 'Other', 'Multiracial', 'Unknown', 'Declined']
            return np.random.choice([x for x in ops if not x==race])
    def create_variant(self,typo_prob = 0.05, synonym_prob = 0.10, choice_prob=0.1,**kwargs):
        ''' create a variant '''
        variant = self.introduce_choice_ers(prob=choice_prob,race=self.name)
        variant = self.introduce_synonyms(prob = synonym_prob,race=variant)
        self.variant = introduce_typos_string(prob = typo_prob,variable=variant)
        return self

class Ethnicity(object):
    ''' class to generate and store ethnicity '''
    ''' assuming a dropdown, so no ers are introduced '''
    def __init__(self):
        self.generate()
    def generate(self):
        totalpop = 328915700
        probs = {
            'Non-Hispanic':      50477594,
            'Hispanic':         258267944
        }
        annotated = np.sum(list(probs.values()))
        probs['Unknown'] = (totalpop - annotated)/2
        probs['Declined'] = (totalpop - annotated)/2
        
        choose = np.random.choice(list(probs.keys()),
                 p=np.array(list(probs.values()))/np.sum(np.array(list(probs.values()))))
        self.name = choose
        return self
    def introduce_synonyms(self,prob,ethnicity):
        ''' introduces often used synonyms '''
        syns = {
            'Hispanic': ['Latino', 'Spanish'],
            'Non-Hispanic': [],
            'Unknown': [],
            "Declined": []
        }
        if np.random.binomial(1,prob):
            if len(syns[ethnicity])>0:
                return str(np.random.choice(syns[ethnicity]))
        return ethnicity
    def introduce_choice_ers(self,prob,ethnicity):
        ops = ['Non-Hispanic','Hispanic', 'Unknown', 'Declined']
        if np.random.binomial(1,1-prob):
            return ethnicity
        else:
            return np.random.choice([x for x in ops if not x==ethnicity])
    def create_variant(self,choice_prob=0.05, synonym_prob = 0.10, **kwargs):
        variant = self.introduce_choice_ers(prob = choice_prob,ethnicity = self.name)
        variant = self.introduce_synonyms(prob = synonym_prob,ethnicity=variant)
        self.variant = variant
        return self

def introduce_typos_string(variable,prob=0.05):
    ''' function to introduce typos in string '''
    newvar = butterfingers.butterfinger(variable,prob=prob)
    return newvar
