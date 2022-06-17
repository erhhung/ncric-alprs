from joblib import Parallel, delayed
import multiprocessing
from sqlalchemy import create_engine, exc
from . import subjectgenerator
import pandas as pd
import numpy as np
import uuid

def generate_person_table(person, jdbc_string=None, dbname=None, synonym_prob=0.05,choice_prob=0.1, typoness = {}, missingness = {}, nicknames = {}, firstletter_prob={}):

    if person%10000 == 0:
        print("Generated person number %i"%person)

    cols = ['trainingId','intId','recordId', 'firstName','middleName','lastName','ssn','sex','dob','race','ethnicity']
    dataframe = pd.DataFrame({k:[] for k in cols})

    # how many times is this subject in our database?
    repeats = np.random.randint(low=1,high=20)

    # initiate subject
    subid = str(uuid.uuid1())
    subject = subjectgenerator.Subject()
    subject.generate()

    # loop over repeats
    for repeat in range(repeats):
        #twins
        subject, twin = subject.create_twin(prob = 0.01/repeats)
        # variants
        variant = subject.create_variant(typoness, missingness,firstletter_prob, nicknames,synonym_prob,choice_prob)
        if not (twin):
            variant['trainingId'] = subid
        else:
            variant['trainingId'] = str(uuid.uuid1())
        dataframe = dataframe.append(variant,ignore_index=True)

    dataframe['intId'] = person

    dataframe['recordId'] = [str(person*100000) + str(x) for  x in range(dataframe.shape[0])]

    dataframe.columns = dataframe.columns.str.lower()
    if isinstance(jdbc_string, str) and isinstance(dbname, str):
        engine = create_engine(jdbc_string)
        try:
            dataframe.to_sql(dbname,engine,if_exists='append', chunksize = 10000, index=False, schema='public')
        except exc.ProgrammingError:
            print("Couldn't write to table")
        engine.dispose()
    else:
        "Insufficient information to write the data to a database."
        return dataframe
    

def generate_table(nsub, jdbc_string=None, dbname=None,synonym_prob=0.05,choice_prob=0.1,typoness = {}, missingness = {}, nicknames = {}, firstletter_prob = {}):
    '''
    Function to generate a table of subject

    :param nsub: The number of subjects in the table
    :type nsub: integer
    :param synonym_prob: The probability of a synonym of the race
    :type synonym_prob: float
    :param choice_prob: The probability of a wrong choice (sex, race, ethn)
    :type choice_prob: float
    '''


    people = Parallel(n_jobs = multiprocessing.cpu_count() - 1) (
        delayed(generate_person_table)(
            person = person,
            jdbc_string = jdbc_string, 
            dbname = dbname,
            typoness = typoness,
            missingness = missingness,
            nicknames = nicknames,
            firstletter_prob = firstletter_prob,
            synonym_prob = synonym_prob,
            choice_prob = choice_prob) for person in range(nsub)
    )

    if not (isinstance(jdbc_string, str) and isinstance(dbname, str)):
        out = pd.concat(people)
        return out

