cheesy-hours
============

Cheesy Hours is a project hour tracking app for the Bellarmine Robotics Lab. Team 254 uses it to track which students
are currently in the lab, and how long in total they have spent there over the course of an FRC season.

Students sign in upon arrival with their student IDs, but cannot sign out on their own. They must approach a mentor, who
can sign them out by sending an SMS message containing their ID to a special phone number, or by logging into the web
interface.

When logged in, students and mentors can view the leaderboard of students ranked by their total hours spent in the lab.

## Adapting for your team's use
### Prerequisites
In order to run this web application, you will need the following:
1. A web server with Ruby and MySQL installed. We use Ruby 2.3.0 and MySQL 5.6. 
1. A Twilio account configured with a phone number for SMS. This will cost you about $1 per month plus $0.01 per message
sent or received.

You will need to pre-create a database (with any name) and a user who has full read/write access to it (or use the root
user).

### Code changes
The current Cheesy Hours code makes many assumptions that are specific to Team 254, which may require authoring
significant new code to get working for your team.

#### Authentication
Team 254 has a custom Single Sign-On (SSO) solution for authenticating users and maintaining the source of truth for the
team roster. This will need to be replaced if protecting access to the web app is required -- see the `before do` block
in [hours_server.rb](hours_server.rb).

#### Authorization
Cheesy Hours enforces that users must have certain permissions in order to perform certain actions (such as signing
out students). This system will likely need to be completely replaced, though hard-coding a list of users and
permissions would be a straightforward way of doing so. Such places in the code are identified by the usage of
`@user.has_permission?()`.

#### Student data syncing
Additionally, Cheesy Hours pulls the student roster from the SSO system to populate the `students` table -- see the `get 
"/reindex_students" do` block in [hours_server.rb](hours_server.rb). One way to work around this would be to manually 
load the student data into the `users` table.

#### Student ID handling
Bellarmine student IDs consist of six numeric digits, but only the last four are needed to uniquely identify students.
As such, there is a shortcut such that either the full ID or just the last four digits can be included in the SMS
message. If this functionality clashes with your ID scheme, edit [students.rb](models/students.rb) to disable it.

### Configuration changes
#### config.json
The environment-specific configurations (i.e. development vs. production) are stored in [config.json](config.json). You
will likely need to update these fields:
1. `db_host`: the address to the MySql database
1. `db_user`: the username of the database user
1. `db_password`: the password of the database user (this can be in plaintext instead of the `Encrypted:` notation)
1. `db_database`: the name of the database that was created for Cheesy Hours
1. `signin_ip_whitelist`: a list of IP addresses to restrict signins to, to prevent students from signing in when away
from the lab to pad their hours (or leaving this blank will disable this functionality)

#### Nginx
Optionally, you can configure Nginx as a reverse proxy in front of the Ruby app, by following
[this guide](https://www.digitalocean.com/community/tutorials/how-to-deploy-a-rails-app-with-unicorn-and-nginx-on-ubuntu-14-04#install-and-configure-nginx).
Team 254 does this because we have multiple Ruby apps on our server, and have Nginx listening on port 80 and routing
requests on each subdomain to their respective Ruby apps listening on non-public ports.

Alternately, you can configure Cheesy Hours to listen on port 80, or access it with a URL containing whichever other
port it is running on (e.g. `http://hours.team254.com:9006`.

#### Twilio
After creating a Twilio account, create a phone number. Leave the "Voice" configuration blank, and configure the
"Messaging" section as follows, replacing `http://hours.team254.com` with the address of your web app but leaving the
`/sms` suffix:

![Twilio messaging configuration screenshot](https://i.imgur.com/s5N4vG1.png)

### Usage
#### Post-startup configuration
Once the application is up and running, import the list of students into the `students` table, and use the "Manage
Mentors" link to whitelist the phone numbers of the mentors who are allowed to sign students out. Give the phone
number of the Twilio account to those mentors and instruct them on usage.

#### Tips
* Multiple space-separated IDs can be included in the same message to sign out multiple students at the same time.
* A message consisting of "GTFO" will sign out all the students who are signed in.