from . import fieldgenerator
import numpy as np

class Subject(object):

    def generate(self):
        sex = fieldgenerator.Sex()
        sex_dict = {"F": "female", "M": "male"}
        sex_recoded = sex_dict[sex.name] if sex.name in sex_dict.keys() else None
        firstname = fieldgenerator.FirstName(gender = sex_recoded)
        middlename = fieldgenerator.MiddleName(gender = sex_recoded)
        lastname = fieldgenerator.LastName()
        ssn = fieldgenerator.Ssn()
        dob = fieldgenerator.Dob()
        race = fieldgenerator.Race()
        ethnicity = fieldgenerator.Ethnicity()
        self.subject_objects = {
            "firstName": firstname,
            "lastName": lastname,
            "middleName": middlename,
            "sex": sex,
            "ssn": ssn,
            "dob": dob,
            "race": race,
            "ethnicity": ethnicity
        }
        self.subject = {
            "firstName": firstname.name,
            "lastName": lastname.name,
            "middleName": middlename.name,
            "sex": sex.name,
            "ssn": ssn.name,
            "dob": dob.name,
            "race": race.name,
            "ethnicity": ethnicity.name
        }
        return self

    def create_variant(self,typoness = {}, missingness = {}, nicknames= {}, firstletter_prob = {}, synonym_prob=0.05,choice_prob=0.05, typo_default = 0, missing_default = 0, nicknames_default=0, firstletter_prob_default=0):
        newsub = {}
        for key in ["firstName","middleName","lastName", "ssn", "sex", "dob", "race", "ethnicity"]:
            if not key in typoness.keys():
                typoness[key] = typo_default
            if not key in missingness.keys():
                missingness[key] = missing_default
            if not key in nicknames.keys():
                nicknames[key] = nicknames_default
            if not key in firstletter_prob.keys():
                firstletter_prob[key] = firstletter_prob_default

        for k,v in self.subject_objects.items():
            if np.random.binomial(1,missingness[k]):
                newval = ""
            else:
                newval = v.create_variant(typo_prob = typoness[k], nickname_prob=nicknames[k], firstletter_prob=firstletter_prob[k], synonym_prob=synonym_prob,
                    choice_prob=choice_prob).variant
            newsub[k] = newval
        return newsub

    def create_twin(self,prob=0.015): #population is about 0.02-0.03, but taking into account that the person flowing through the system is more likely the same...
        twin = False
        if np.random.binomial(1,prob):
            firstname = fieldgenerator.FirstName()
            middlename = fieldgenerator.MiddleName()
            sex = fieldgenerator.Sex()
            ssn = fieldgenerator.Ssn()
            self.subject_objects = {
                "firstName": firstname,
                "middleName": middlename,
                "lastName": self.subject_objects['lastName'],
                "sex": sex,
                "ssn": ssn,
                "dob": self.subject_objects['dob'],
                "race": self.subject_objects['race'],
                "ethnicity": self.subject_objects['ethnicity']
            }
            self.subject = {
                "firstName": firstname.name,
                "middleName": middlename.name,
                "lastName": self.subject_objects['lastName'].name,
                "sex": sex.name,
                "ssn": ssn.name,
                "dob": self.subject_objects['dob'].name,
                "race": self.subject_objects['race'].name,
                "ethnicity": self.subject_objects['ethnicity'].name
            }
            twin = True
        return self, twin

    
