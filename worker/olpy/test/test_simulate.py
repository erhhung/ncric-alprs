import unittest
from olpy import simulate

class TestSimulate(unittest.TestCase):

    def test(self):

        typoness = {
            "firstName": 0.001,
            "middleName": 0.001,
            "lastName": 0.001,
            "ssn": 0,
            "sex": 0,
            "dob": 0,
            "race": 0,
            "ethnicity": 0
        }
        missingness = {
            "firstName": 0.1,
            "middleName": 0.1,
            "lastName": 0.1,
            "ssn": 0.4,
            "sex": 0.2,
            "dob": 0.4,
            "race": 0.1,
            "ethnicity": 0.2
        }

        nicknames = {
            "firstName": 0.5,
            "middleName": 0.5
        }

        firstletter_prob = {
            "firstName": 0.1,
            "middleName": 0.5
        }

        table = simulate.tablegenerator.generate_table(nsub=int(10),
                               typoness=typoness,
                               missingness=missingness,
                               nicknames=nicknames,
                               firstletter_prob=firstletter_prob,
                               synonym_prob=0,
                               choice_prob=0
                               )
        self.assertEqual( table.trainingid.unique().shape[0], 10)

if __name__ == '__main__':
    unittest.main()
