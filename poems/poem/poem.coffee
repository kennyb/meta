
class Main extends Panel
	template: """
	this is the main panel
	"""

class MainMobile extends Main
	width_lt: 800
	template: """
	this is the mobile main panel
	"""

class PoemApp extends Poem
	template: """
		<header>this is the header</header>
		<sidebar>this is the sidebar</sidebar>
		<content>this is the content</content>
	"""
	panels: {
		main: Main
		create: 
	}