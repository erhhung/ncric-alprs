from setuptools import setup, find_packages

setup(name='pyntegrationsncric',
      version='0.0.1',
      description='NCRIC Integration Definitions for OpenLattice',
      author='OpenLattice',
      author_email='info@openlattice.com',
      packages=find_packages(),
      dependency_links=[],
      install_requires=[
          'boto3',
          'dask',
          'pandas'
      ],
      package_data={'':['*.yaml','*.csv']},
      zip_safe=False
)
