"""GRNET fork: the pages our branding and the SCA card choice changed.

Rendered through the app, so the Content-Security-Policy of 0.11.0 is in force:
inline scripts need the page's nonce, and inline event handlers are refused.
"""
import json
import re


# client: the fixture in conftest.py (the app with a stubbed backend).

CARD_ART = "https://fe.test/static/card_art_mastercard.png"
CARD_CHOICE = {
    "type": "card_choice",
    "mandatory": True,
    "options": [
        {"value": "Partner Bank Mastercard|1234", "label": "Partner Bank Mastercard",
         "image_url": CARD_ART, "last_four": "1234", "expiry": "11/28"},
        {"value": "Gold Mastercard|5678", "label": "Gold Mastercard",
         "image_url": CARD_ART, "last_four": "5678", "expiry": "11/28"},
    ],
}
CARD_DISPLAY = {
    "type": {"code": "CREDIT", "label": "Credit card"},
    "last_four": "1234",
    "card_art": [{"theme": "DEFAULT", "image_url": CARD_ART}],
    "alias": "Partner Bank Mastercard",
    "issuer": {"branding": {"name": "Partner Bank"}},
    "network_branding": {"network": "mastercard", "branding": {"name": "Mastercard"}},
    "expiry": "11/28",
}


def _post(client, path, payload):
    return client.post(path, data={"payload": json.dumps(payload)})


def _no_inline_handlers(html):
    assert not re.search(r"\son(submit|click|change|load)=", html), "inline event handler"


def _scripts_have_nonce(response):
    csp = response.headers["Content-Security-Policy"]
    nonce = re.search(r"'nonce-([^']+)'", csp).group(1)
    html = response.get_data(as_text=True)
    for tag in re.findall(r"<script\b[^>]*>", html):
        assert "src=" in tag or f'nonce="{nonce}"' in tag, tag


def test_form_shows_the_card_choice(client):
    r = _post(client, "/display_form", {
        "mandatory_attributes": {"card": CARD_CHOICE},
        "optional_attributes": {},
        "redirect_url": "https://backend.test/dynamic/form",
    })
    assert r.status_code == 200
    html = r.get_data(as_text=True)
    assert "Choose your card" in html
    assert 'value="Gold Mastercard|5678"' in html
    assert "•••• •••• •••• 1234" in html
    assert "GRNET Demo Issuer" in html and "css/grnet.css" in html
    # No optional attributes, no button to add them.
    assert 'id="add-optional-btn"' not in html
    _no_inline_handlers(html)
    _scripts_have_nonce(r)


def test_consent_page_shows_the_card(client):
    r = _post(client, "/display_authorization", {
        "presentation_data": {"SCA Card": {"card_display": CARD_DISPLAY, "issuing_authority": "Partner Bank"}},
        "redirect_url": "https://backend.test/dynamic/redirect_wallet",
        "user_id": "u1",
    })
    assert r.status_code == 200
    html = r.get_data(as_text=True)
    assert "Partner Bank Mastercard" in html
    assert "Credit card · •••• 1234" in html
    assert "Payment Network" in html and "Mastercard" in html
    assert "card_display" not in html
    _no_inline_handlers(html)
    _scripts_have_nonce(r)


def test_layout_carries_the_branding(client):
    r = client.get("/")
    assert r.status_code == 200
    html = r.get_data(as_text=True)
    assert "GRNET Demo Issuer" in html
    assert "logo_govgr_beta_pos.svg" in html
    assert "Demo services - Test data only." in html
