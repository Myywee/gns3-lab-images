from flask import Flask, redirect, render_template_string, request, session

app = Flask(__name__)
app.config.update(
    SECRET_KEY="exp3-insecure-teaching-key",
    SESSION_COOKIE_SECURE=True,
    SESSION_COOKIE_HTTPONLY=False,
    SESSION_COOKIE_SAMESITE="None",
)

messages = []
users = {"admin": "admin123"}


def current_user():
    return session.get("username")


@app.get("/")
def index():
    return render_template_string(
        """<!doctype html>
<html lang="en"><meta charset="utf-8"><title>Exp3 Vulnerable App</title>
<body><h1>Experiment 3 Vulnerable Web App</h1>
<p>{% if user %}Current user: {{ user }}{% else %}Not logged in{% endif %}</p>
<nav><a href="/search?q=hello">Search</a> |
<a href="/guestbook">Guestbook</a> |
{% if user %}<a href="/profile">Profile</a> |
<a href="/logout">Logout</a>{% else %}<a href="/login">Login</a>{% endif %}</nav>
<h2>Messages</h2>
{% for message in messages %}<p>{{ message|safe }}</p>{% endfor %}
</body></html>""",
        user=current_user(),
        messages=messages,
    )


@app.get("/search")
def search():
    q = request.args.get("q", "")
    return (
        """<!doctype html><html lang="en"><meta charset="utf-8">
<title>Search</title><body><h1>Search</h1>
<form><input name="q"><button>Search</button></form>
<p>Search result for: """ + q + """</p><a href="/">Back</a>
</body></html>"""
    )


@app.route("/guestbook", methods=["GET", "POST"])
def guestbook():
    if request.method == "POST":
        messages.append(request.form.get("message", ""))
        return redirect("/")
    messages_html = "".join(f"<p>{m}</p>" for m in messages)
    return f"""<!doctype html><html lang="en"><meta charset="utf-8">
<title>Guestbook</title><body><h1>Guestbook</h1>
<form method="post"><textarea name="message"></textarea><button>Submit</button></form>
<h2>All Messages</h2>{messages_html}<a href="/">Back</a></body></html>"""


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form.get("username", "")
        password = request.form.get("password", "")
        if users.get(username) == password:
            session["username"] = username
            return redirect("/")
        return "Login failed", 401
    return """<!doctype html><html lang="en"><meta charset="utf-8">
<title>Login</title><body><h1>Login</h1><form method="post">
<input name="username" placeholder="Username">
<input name="password" type="password" placeholder="Password">
<button>Login</button></form></body></html>"""


@app.get("/profile")
def profile():
    if not current_user():
        return redirect("/login")
    return """<!doctype html><html lang="en"><meta charset="utf-8">
<title>Profile</title><body><h1>Change Password</h1>
<form action="/change-password" method="post">
<input name="new_password" type="password"><button>Change Password</button></form>
<a href="/">Back</a></body></html>"""


@app.post("/change-password")
def change_password():
    user = current_user()
    if not user:
        return "Not logged in", 401
    new_password = request.form.get("new_password", "")
    if not new_password:
        return "Password cannot be empty", 400
    users[user] = new_password
    return "Password changed successfully!"


@app.get("/logout")
def logout():
    session.clear()
    return redirect("/")


@app.get("/healthz")
def healthz():
    return {"status": "ok", "mode": "vulnerable"}


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000)
