from setuptools import setup, find_packages

def get_requirements():
    with open("requirements.txt", "r") as file:
        return file.read().splitlines()

def get_long_description():
    with open("README.md", "r") as readme:
        return readme.read()

setup(
    name="noetl-plugins",
    version="0.1.6",
    author="NoETL Team",
    description="A collection of plugins for NoETL",
    long_description=get_long_description(),
    long_description_content_type="text/markdown",
    packages=find_packages(),
    install_requires=get_requirements(),
)
