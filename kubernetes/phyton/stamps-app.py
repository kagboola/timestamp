from flask import Flask, render_template, request, redirect
from flask_mysqldb import MySQL
import time
import datetime
import os

app = Flask(__name__)

# Configure db
#db = yaml.load(open('db.yaml'))
# MySQL configurations
app.config['MYSQL_HOST'] = "stamps-app.cugmzubqhre7.eu-west-1.rds.amazonaws.com"
app.config['MYSQL_USER'] = "admin"
app.config['MYSQL_PASSWORD'] = os.getenv("db_root_password")
app.config['MYSQL_DB'] = "stamps_app"

mysql = MySQL(app)

ts = time.time()
timestamp = datetime.datetime.fromtimestamp(ts).strftime('%Y-%m-%d %H:%M:%S')

@app.route('/', methods=['GET', 'POST'])
def index():
    if request.method == 'POST':
        # Fetch form data
        userDetails = request.form
        name = userDetails['name']
        email = userDetails['email']
        cur = mysql.connection.cursor()
        cur.execute("INSERT INTO users(name, email, time_value) VALUES(%s, %s, %s)",(name, email,timestamp))
        mysql.connection.commit()
        cur.close()
        return redirect('/users')
    return render_template('index.html')

@app.route('/users')
def users():
    cur = mysql.connection.cursor()
    resultValue = cur.execute("SELECT * FROM users")
    if resultValue > 0:
        userDetails = cur.fetchall()
        return render_template('users.html',userDetails=userDetails)

if __name__ == '__main__':
    app.run(host='0.0.0.0',port=5000,debug=True)


