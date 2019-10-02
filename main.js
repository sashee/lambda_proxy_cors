const getCookiesFromHeader = (headers) => {
	if (headers === null || headers === undefined) {
		return {};
	}

	// Split a cookie string in an array (Originally found http://stackoverflow.com/a/3409200/1427439)
	const list = {},
		rc = headers.Cookie || headers.cookie;

	rc && rc.split(";").forEach(( cookie ) => {
		const parts = cookie.split("=");
		const key = parts.shift().trim();
		const value = decodeURI(parts.join("="));
		if (key != "") {
			list[key] = value;
		}
	});

	return list;
};

const corsHeaders = (headers) => {
	const origin = headers.origin || headers.Origin;
	if (process.env.ALLOWED_ORIGINS.split(" ").includes(origin)) {
		return {
			"Access-Control-Allow-Origin": origin,
			"Access-Control-Allow-Credentials": "true",
			"Vary": "Origin",
		};
	}
};

module.exports.handler = async (event, context) => {
	if (event.path === "/login") {
		return {
			statusCode: 200,
			headers: {
				"Set-Cookie": "user=Bob",
				...corsHeaders(event.headers),
			},
		};
	}else if (event.path === "/logout") {
		return {
			statusCode: 200,
			headers: {
				"Set-Cookie": "user=anonymous; expires=Thu, 01 Jan 1970 00:00:00 GMT",
				...corsHeaders(event.headers),
			},
		};
	}else {
		const user = getCookiesFromHeader(event.headers).user || null;
		if (user) {
			return {
				statusCode: 200,
				headers: {
					...corsHeaders(event.headers),
				},
				body: `Logged in as ${user}`,
			};
		}else {
			return {
				statusCode: 200,
				headers: {
					...corsHeaders(event.headers),
				},
				body: "Logged out",
			};
		}
	}
};

