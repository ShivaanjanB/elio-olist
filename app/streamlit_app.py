"""Olist explorer: three pages over the results of the pipeline.

    cd app
    ..\\.venv\\Scripts\\streamlit.exe run streamlit_app.py

With the Snowflake variables loaded (see README) it reads the marts live; without them it shows a saved snapshot.
"""
import streamlit as st

from olist_app import data

st.set_page_config(
    page_title="Olist: deliveries, reviews and repeat purchase",
    page_icon=":material/local_shipping:",
    layout="wide",
)

pages = [
    st.Page("app_pages/delivery.py", title="Deliveries and reviews", icon=":material/local_shipping:", default=True),
    st.Page("app_pages/coming_back.py", title="Coming back", icon=":material/repeat:"),
    st.Page("app_pages/voucher_test.py", title="Voucher test", icon=":material/calculate:"),
]
current = st.navigation(pages)

with st.sidebar:
    st.caption(data.source_note(data.load()))

current.run()
